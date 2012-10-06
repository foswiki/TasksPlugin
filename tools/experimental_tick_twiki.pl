#!/usr/bin/perl -w
#*/usr/bin/perl -wd
# Runs setuid/setgid - to debug, flags must match perl command.
#
# TWiki periodic tasks - rewritten and extended from tick_twiki.pl
#
# Copyright (C) 2011 Timothe litt <litt at acm dot org>
# Full copyright after __END__

### BEGIN INIT INFO
# Provides: TWiki
# Required-Start: $local_fs $network $named $portmap $remote_fs $syslog
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Description: TWiki daemon controlling scheduled tasks
### END INIT INFO

# ###
# chkconfig: 2345 90 10
# description: TWiki daemon controlling scheduled tasks
# ###

use warnings;
use strict;

use Config qw/%Config/;
use Cwd qw/realpath/;
use Errno qw(EAGAIN);
use Getopt::Std;
   $Getopt::Std::STANDARD_HELP_VERSION = 1;
use File::Basename;
use POSIX qw(:sys_wait_h);
use Schedule::Cron;

my $bindir;

BEGIN {
    # Obtain configuration - avoid using yet another file
    #
    # Required for running as an init script

    eval {
	# Find the desired twiki libraries
	# This also supports sites that run multiple version under one webserver
	#
	# Setup:
	#  This script may be the target of a softlink (e.g. from /etc/init.d)
	#  A soflink of <$0>_bin points to the location of setlib.cfg
	#
	# For a second wiki:
	#  hardlink from this script to another name - e.g. tick_twiki2
	#  Add another softlink from /etc/init.d/ to the alternate name e.g. tick_twiki2
	#  Add softlink from the alternate name to the alternate setlib.cfg directory
	#
	# Note the *HARD* link prevents the need to make another copy of this script.
	# You can't use a softlink.  (If your system doesn't support hard links, make a copy.)
	#
	# Repeat as desired - or reqired.

	# Find this script's physical location
	my $script = realpath( $0 );

	# Find the link to the directory containing setlib.cfg
	$bindir = realpath( "${script}_bin" ) || realpath( "$script/../bin" );

	# Now find the root directory = 1 above the bindir
	my $rootdir = dirname $bindir;

	chdir $rootdir;
	unshift @INC, $bindir;
    };
    unshift @INC, '.';
    require 'setlib.cfg';
}

# Support multiple wikis
#
# etc/init.d/wikistart is softlinked to www/wiki/tools/tick (this)
# softlink tick_bin to bin directory
#
# For second wiki
# hardlink tick to tick2
# softlink init.d/wiki2start to tick2
# softlink tick2_bin to other bin directory
# Repeat as desired.  

# Security enforcement for system startup
# This script should run setuid and setgid, so we know the webserver (or other unprive) ids
#
# These will fail if we are an unprivileged user

if( $> == 0 || $< == 0 ) {
    # Make sure we are running under the specified user and group.

    # Drop ability to raise privs
    #
    # Get webserver user and group
    my( $uid,$gid ) = ( $>, $)+0 );
    $! = 0;
    # Raise privs so we can modify
    $> = $<;
    die "Can't set user $<: $!" if( $! );
    # Set real to server
    $( = $gid;
    die "Can't set group $gid: $!" if( $! );
    # Drop extra groups
    $) = "$gid $gid";
    die "Can't set group $gid: $!" if( $! );
    # Set real to server
    $< = $uid;
    die "Can't set user $uid: $!" if( $! );
    # Finally, set effective to server
    $> = $uid;
    die "Can't set user $uid: $!" if( $! );
}

die "Must not run under root - are permissions setuid/setgid?\n"
  if( $> == 0 || $< == 0 || $(+0 == 0 || $)+0 == 0 );

use Foswiki;
use Foswiki::Func;
use Foswiki::LoginManager;

### Debugging
# use Data::Dumper; $Data::Dumper::Sortkeys = 1;
###

our $VERSION = '2.0-005';
sub HELP_MESSAGE;

# Logging levels
use constant {
                 INFO => 0,
		 WARN => 1,
		 ERROR => 2,
	     };

my %sigmap;
{
    my @nums = split( ' ', $Config{sig_num} );
    my @names = split( ' ', $Config{sig_name} );
    while( @nums ) {
	$sigmap{$names[0]} = $nums[0];
	$sigmap{shift(@nums)} = shift(@names);
    }
}

my $reaper = 'IGN';

our $cronhandle;
my $cfgfilename = 'LocalSite.cfg';
our $cfgModTime = (stat $INC{$cfgfilename})[9] or die "Failed to stat $cfgfilename\n";
our %cfgModRegistry;

my $umask = $Foswiki::cfg{Periodic}{Umask};
$umask = 007 unless( defined $umask );
umask( $umask );

my %opts;

my $sws = 'dv:flxgp:';
getopts( $sws, \%opts );
    # -d enable debugging
    #  -v Verbose - loglevel
    # -f Run in foreground even if not debugging.
    # -l Don't run login cleanup
    # -x Don't run expired lease cleanup
    # -g Don't run plugin cleanup
    # -p: pidfile spec

my $debug = 0;
if( exists $opts{v} ) {
    $debug = 1;
} else {
    $opts{v} = WARN;
}

if( $opts{d} ) {
    $debug = 1;
}
$opts{p} ||= ( $Foswiki::cfg{WorkingDir} . '/' || 'working/' ) . 'tick_daemon.pid';

# Dispatch commands

my $cmd = shift @ARGV;

if( !$cmd || $cmd eq 'condstart' ) {
    exit start() unless( daeok() );
    exit 0;
} elsif( $cmd eq 'status' ) {
    exit status( @ARGV );
} elsif( $cmd eq 'start' ) {
    exit start();
} elsif( $cmd eq 'stop' ) {
    exit stop();
} elsif( $cmd eq 'restart' ) {
    exit stop() || start();
} elsif( $cmd eq 'condrestart' ) {
    exit 1 unless( daeok() );
    exit stop() || start();
} elsif( $cmd eq 'help' ) {
    print "Use --help for help\n";

    exit 1;
} else {
    print "Unrecognized command, use --help for assistance\n";
    exit 1;
}

# Report status, optionally signally daemon to dump interesting state to debug log

sub status {
    my @args = @_;

    if( my $pid = daeok() ) {
	print "Daemon is running ($pid)\n";
	if( @args && $args[0] eq 'dump' ) {
	    kill( 'HUP', $pid );
	    print "Check TWiki debug log for queue listing\n";
	}
	return 0;
    } else {
	print "Daemon is stopped\n";
	return 1;
    }
}

# Start daemon process

sub start {
    if( daeok() ) {
	print "Daemon is already running\n";
	return 1;
    }

    # For now, run the tasks single-threaded in this process to reduce chance of conflicts
    # Exceptions in a task will be caught and logged
    # Each task's exit status is checked
    #

    my $cron = new Schedule::Cron( \&defaultSched, {
						    nofork => 1,
						    catch => 1,
						    after_job => \&checkJob,
						    log => \&cronlog,
						    loglevel => $opts{v},
						    nostatus => 1,
						    processprefix => basename( $0 ),
						    } );
    $cronhandle = $cron;

    # Setup signal handlers for status and termination

    $SIG{HUP} = \&sigHUP;
    $SIG{TERM} = \&sigTERM;
    $SIG{INT} = \&sigINT;

    # N.B. First arg of entry is used as an ID, so it must be the task name
    $cron->add_entry( "* * * * * *", { subroutine => \&initWiki, 
				       args => [ 'initWiki',
						 'none',
						 \%opts, $cron ],
				      } );

    my %runopts = (
		   pid_file => $opts{p},
		   detach => 1,
		  );
    delete $runopts{detach} if( $debug || $opts{f} );

    # If debugging, this will never return and will process in the foreground

    my $pid = $cron->run( \%runopts );

    print "Started Daemon ($pid)\n";

    return 0;
}

# Stop daemon process

sub stop {
    if( my $pid = daeok() ) {
	if(  kill( 'TERM', $pid ) ) {
	    print "Stopped daemon ($pid)\n";
	    return 0;
	}
	print "Failed to signal daemon ($pid)\n";
	return 1;
    } else {
	print "Daemon is already stopped\n";
	return 1;
    }
}

# See if daemon is running, returning pid or 0

sub daeok {
    my $pid = daepid();

    return $pid if( $pid && $pid > 0 );

    return 0;
}

# Obtain pid from pidfile and return running status

sub daepid {
    open( my $fh, '<', $opts{p} ) or return undef;

    my $pid = <$fh>;

    close $fh;

    $pid =~ m/^(\d+)$/;
    $pid = $1;

    return -1 unless( kill( 0, $pid ) );

    return $pid;
}

exit 1;

# Default entry scheduler - we don't create the type of entry that uses it.

sub defaultSched {
    # An entry exists without a task subroutine
    # We don't ever do this.

    die "Default dispatcher called: @_";
}

# Logging interface to scheduler

# shorten object dumps in debug messages

sub curse {
    my $msg = shift;

    my $mout = '';

    while( $msg =~ s/^(.*?bless\( \{)// ) {
	$mout .= $1;
	my @rest = split( //, $msg );
	my $lvl = 0;
	my $end = 0;
	foreach my $c (@rest) {
	    $end++;
	    last if( $c eq '}' && !$lvl );
	    $lvl++, next if( $c eq '{' );
	    $lvl--, next if( $c eq '}' );
	}
	$mout .= '...}';
	$msg = join( '', @rest[$end..$#rest] );
    }
    $mout .= $msg;
    return $mout;
}

# Split a message into lines, apply prefix and print

# Stub routines for debugging or TWiki not initialized
# Print normally - append the \n that TWiki does.
sub tprint {
    print( $_[0], "\n" );
}
sub eprint {
    print STDERR $_[0], "\n";
}
# Parallel to Foswiki::Func::writeWarning (including Foswiki::writeWarning)
# (Could be a core function)
sub writeError {
    # STDERR is probably /dev/null
    #    print STDERR $_[0];

    # Func::writeError
    my( $message ) = @_;
    $message = "(".caller().") " . $message;
    # Foswiki::writeError
    $Foswiki::Plugins::SESSION->_writeReport( $Foswiki::cfg{ErrorFileName}, $message  );
}

# Break multi-line messages apart, adding prefix & removing \n

sub logLines {
    my( $pfx, $msg, $print ) = @_;

    foreach my $line (split( /\n/, $msg )) {
	$line = "$pfx$line";
	$print->( $line );
    }
}

# Log a message

sub cronlog {
    my( $level, $msg ) = @_;

    if( !$Foswiki::Plugins::SESSION || $debug ) {

	# Logging to terminal

	my $stamp = localtime();

	if( $level == INFO ) {
	    if( $debug ) {
		unless( $opts{v} <= -1 ) {
		    $msg = curse( $msg );
		}
		logLines( "Periodic Task[$$](I) $stamp: ", $msg, \&tprint );
	    }
	} elsif( $level == WARN ) {
	    logLines( "Periodic Task[$$](W) $stamp: ", $msg, \&tprint );
	} else {
	    logLines( "Periodic Task[$$](E) $stamp: ", $msg, \&tprint );
	}

	return;
    }
    # Note that the TWiki log routines all add a \n to the end of each message.
    if( $level == INFO ) {
	if( $debug ) { # Not used except for debugging logging
	    unless( $opts{v} <= -1 ) {
		$msg = curse( $msg );
	    }
	    logLines( "Periodic Task[$$](I): ", $msg, \&Foswiki::Func::writeDebug );
	}
    } elsif( $level == WARN ) {
    	logLines( "Periodic Task[$$](W): ", $msg, \&Foswiki::Func::writeWarning );
    } else {
	logLines( "Periodic Task[$$](E): ", $msg, \&writeError );
    }
}

# End of job status check
# Called by cron at completion of each task

sub checkJob {
    my $sts = shift;
    my $name = shift;
    my $session = shift;

    $sts = 1 unless( defined $sts );

    cronlog( INFO, "$name finished successfully" ) if( $sts == 0 && $debug );
    cronlog( WARN, "$name exited with status $sts" ) if( $sts );
}

# This task is scheduled for the first event on startup.
# The point of doing it here is that we don't initialze the TWiki session
# for the command shell; at this point we've forked to the daemon process.
#
# Initialize the session, enabling all plugins/extensions to schedule their
# tasks.

sub initWiki {
    my( $name, undef, $opts, $cron ) = @_;

    # Remove the only entry - the one that called us

    $cron->clean_timetable();

    # Export the API to the Foswiki::Func:: namespace for consistency
    # Do everything twice to suppress "Name used only once" errors

    foreach my $api (qw /AddTask AddAsyncTask DeleteTask NextRuntime ReplaceSchedule RegisterConfigChangeHandler/) {
	no strict 'refs';
	no warnings 'redefine';
	*{ "Foswiki::Func::$api" } = \&{ "Foswiki::Periodic::$api" };
	*{ "Foswiki::Func::$api" } = \&{ "Foswiki::Periodic::$api" };
	use warnings 'redefine';
	use strict 'refs';
    }

    # Initialize the session

    # Plugins will register their tasks as they initialize;

    my $twiki = new TWiki( $Foswiki::cfg{Periodic}{UserName}, undef, {
								    command_line => 1,
								    Periodic_Task => 1,
								   } );
    $Foswiki::Plugins::SESSION = $twiki;

    # Intercept STDERR -- N.B. Requires session because otherwise prints to STDERR...

    tie *STDERR, 'Foswiki::STDERR', sub {
	                                  cronlog( ERROR, @_ );
					  return 1;
				      };

    cronlog( INFO, "initWiki" );

    # Setup to reap any async task's forks

    my $prevReaper = $SIG{'CHLD'};
    $reaper = sub {
	              &REAPER();
		      if( $prevReaper && ref $prevReaper eq 'CODE' ) {
			  &$prevReaper();
		      }
		  };
     $SIG{'CHLD'} = $reaper;

    # Schedule the traditional tick_twiki maintenance task.
    # Also schedule a task to handle configuration file changes.
    # Register for changes on items we cache.

    package Foswiki::Periodic;
    AddTask( 'TickTock', \&main::tick_twiki, undef, $opts );

    AddTask( 'ReConfig', \&main::check_config, ($Foswiki::cfg{Periodic}{ReConfigSchedule} || "*/5 * * * * 17"), 
	                                       $INC{$cfgfilename}, \$cfgModTime, \%cfgModRegistry );

    RegisterConfigChangeHandler( '{CleanupSchedule}', \&main::reconfig, 'Foo' );

    RegisterConfigChangeHandler( [ '{CleanupSchedule}',
				   '{Periodic}{ReConfigSchedule}',
				   '{Periodic}{Umask}',
				   '{Periodic}{UserName}',
				 ], \&main::reconfig );
    package main;

    logLines( "\t", statusText(), \&tprint ) if( $debug );

    return 0;
}

# Handle configuration changes

sub reconfig {
    my( $twiki, $changes ) = @_;

    foreach my $change (keys %$changes) {
	my $value = $changes->{$change};
	({
	     '{CleanupSchedule}' => sub {
		                            package Foswiki::Periodic;
					    ReplaceSchedule( 'TickTock', undef );
					    package main;
				        },
	     '{Periodic}{ReConfigSchedule}' => sub {
		                                       package Foswiki::Periodic;
						       ReplaceSchedule( 'ReConfig', ($Foswiki::cfg{Periodic}{ReConfigSchedule} || "*/5 * * * * 17" ) );
						       package main;
						   },
	     '{Periodic}{Umask}' => sub {
		                            my( $change, $value ) = @_;
		                            umask( $value || 007 );
				        },
	     '{Periodic}{UserName}' => sub {
#		                               my( $change, $value ) = @_;
#		                               $twiki-> change_user_name( $value );
	                                   },
	}->{$change} || sub { })->($change, $value);
    }

    return;
}

# Look for configuration file changes & reload if necessary
#
# Notify any plugins that registered for (actual) changes

sub check_config {
    my( $name, $twiki, $cfgfile, $modtime, $registry ) = @_;

    # Check file only once for each modification time change

    my $newmod = (stat $cfgfile)[9] || 0;
    my $prevmod = $$modtime;

    return 0 unless( defined $newmod && $newmod != $prevmod );

    $$modtime = $newmod;

    cronlog( INFO, "Detected configuration file change, re-processing\n" );

    # Re-read the file, catching any syntax or other errors

    my %oldcfg = %Foswiki::cfg;
    %Foswiki::cfg = ();

    eval {
	unless( my $sts = do $cfgfile ) {
	    die "Couldn't parse $cfgfile: $@\n" if( $@ );
	    die "Couldn't read $cfgfile: $!" unless( defined $sts );
	    die "Unsuccessful status from $cfgfile\n" unless( $sts );
	};
    }; if( $@ ) {
	$Foswiki::cfg = %oldcfg;
	cronlog( WARN, "Continuing with previous configuration: @!\n" );
	return 0;
    }
    foreach my $task (keys %$registry) {
	my $reg = $registry->{$task};

	# See if change in any registered item of interest to this task

	my %changed;
	foreach my $item (@{$reg->{items}}) {
	    my $oval = eval "\$oldcfg$item";
	    my $nval = eval "\$Foswiki::cfg$item";
	    $changed{$item} = $nval if( (defined($oval) xor defined($nval))
				       || defined($nval) && $oval ne $nval );
	}
	if( %changed ) {
	    cronlog( INFO, "Notifying $task of changes to " . join( ',', sort keys %changed ) . "\n" ) if( $debug );
	    $reg->{sub}( $twiki, \%changed, @{$reg->{args}} );
	}
    }
    return 0;
}

# Standard maintenance task
#
# This is the work done by the old tick_twiki script
# It also guarantees that at least one task is present.
#  Schedule::Cron falls over if its queue is empty.

sub tick_twiki {
    my( $name, $twiki, $opts ) = @_;

    unless( $opts->{l} ) {
	# This will expire sessions that have not been used for
	# |{Sessions}{ExpireAfter}| seconds i.e. if you set {Sessions}{ExpireAfter}
	# to -36000 or 36000 it will expire sessions that have not been used for
	# more than 100 hours,

	cronlog( INFO, "Expire sessions" );

	Foswiki::LoginManager::expireDeadSessions();
    }

    my $now = time();

    unless( $opts->{x} ) {
	# This will remove topic leases that have expired. Topic leases may be
	# left behind when users edit a topic and then navigate away without
	# cancelling the edit.

	cronlog( INFO, "Expire leases" );

	my $store = $twiki->{store};

	foreach my $web ( $store->getListOfWebs()) {
	    $store->removeSpuriousLeases($web);
	    foreach my $topic ( $store->getTopicNames( $web )) {
		my $lease = $store->getLease( $web, $topic );
		if( $lease && $lease->{expires} < $now) {
		    $store->clearLease( $web, $topic );
		}
	    }
	}
    }

    unless( $opts->{g} ) {

	# Run plugin garbage collectors on standard schedule

	cronlog( INFO, "Cleanup plugins" );

	foreach my $plugin ( @{$twiki->{plugins}{plugins}} ) {
	    next if( $plugin->{disabled} );

	    local $Foswiki::Plugins::SESSION = $twiki;

	    my $cleanup = $plugin->{module} . '::pluginCleanup';

	    if( defined( &$cleanup ) ) {
		cronlog( INFO, " -- $cleanup" );
		no strict 'refs';
		eval {
		    &$cleanup( $twiki, $now );
		};
		use strict 'refs';
		cronlog( ERROR, "Exception from $cleanup: $@" ) if( $@ );
	    }
	}
    }

    return 0;
}

# Get package from a task name so we run tasks in  their packages

sub taskPackage {
    my $name = shift;

    $name =~ /^(.*)::(.*)?$/;
    return $1;
}

# Internal task run when an async task is scheduled
# Create a fork to run the requested routine and setup an environment for it.

sub ForkTask {
    my $name = shift;   # Task name
    my $session = shift; # twiki
    my $sub = pop;      # Worker routine

    my $ppid = $$;
  FORK: {
	    my $pid;
	    if( $pid = fork ) {
		cronlog( INFO, "Started $name as pid $pid" );
		return 0;
	    } elsif( defined $pid ) {
		$0 = basename( $0 ) . " - $name (master = $ppid)";
		@ARGV = ();

		# Do not inherit signal handlers

		$SIG{HUP} = 'DEFAULT';
		$SIG{TERM} = 'DEFAULT';
		$SIG{INT} = 'DEFAULT';
		$SIG{CHLD} = 'DEFAULT';

		open STDIN, '/dev/null' or die "Can't read /dev/null: $!";
		open STDOUT, '>/dev/null' or die "Can't write to /dev/null: $!" unless( $debug );
		{
		    my $to = tied( *STDERR );
		    if( $to ) {
			undef $to;
			untie *STDERR;
		    }
		}
		open STDERR, '>&STDOUT' or die "Can't dup stdout: $!";
		tie *STDERR, 'Foswiki::STDERR', sub {
		                                      cronlog( ERROR, join( '', @_ ) );
						      return 1;
						  };

		# Since we are running in a separate fork, the APIs that need to modify data
		# in the daemon can't work.  Catch any attempted use and signal confusion.

		foreach my $api (qw /AddTask AddAsyncTask DeleteTask ReplaceSchedule RegisterConfigChangeHandler/) {
		    no strict 'refs';
		    no warnings 'redefine';
		    *{ "Foswiki::Func::$api" } = sub {
                                                       die "$name [$$] Foswiki::Func::$api can not be called from an asynchronous task" .
							 ($opts{v} <=0 ? sprintf( ' at %s::%s line %u', (caller)[0,1,2] ) : '') . "\n";
						   };
		    use warnings 'redefine';
		    use strict 'refs';
		}
		my $sts = eval {
		                   &$sub( $name, $session, @_ );
			       };
		if( $@ ) {
		    cronlog( ERROR, "[$$] Exception from $name: $@\n" );
		    $sts = 254;
		} else {
		    if( $sts ) {
			cronlog( ERROR, "[$$] $name returned with error status ($sts)" );
		    } else {
			cronlog( INFO, "[$$] $name completed successfully" );
			$sts ||= 0;
		    }
		}
		exit $sts;
	    } elsif( $! == EAGAIN ) {
		sleep 5;
		redo FORK;
	    } else {
		die "Unable to fork $name: $!\n";
	    }
	}
    return 1; # Shouldn't get here..
}

sub REAPER {
    local( $!, %! );   # don't let waitpid() overwrite current error
    while( (my $pid = waitpid( -1, WNOHANG )) > 0 ) {
	if( WIFEXITED($?) ) {
	    cronlog( INFO, "Asynchronous task $pid exited with status " . WEXITSTATUS($?) . "\n" );
        } elsif( WIFSIGNALED($?) ) {
	    cronlog( INFO, "Asynchronous task $pid terminated by SIG" . ($sigmap{WTERMSIG($?)} || '???') . "\n" );
	}
    }
    $SIG{CHLD} = $reaper;  # sysV
}

######################################################################
# API for the rest of TWiki

package Foswiki::Periodic;

# Add a task to the schedule
# Called by plugins and extensions

sub AddTask {
    my $name = shift;   # Task name (used for logging and to delete task)
                        # Must be unique
    my $sub = shift;    # Subroutine containing task
                        # ( $name, $session, @args )
    my $schedule = shift; # crontab format schedule  (vixiecron + optional seconds col)
                          # or preference name containing one
                          # Default is standard tick schedule

    my $cron = $main::cronhandle;

    die "Invalid arguments to AddTask" unless( defined $name && $name !~ /::/ && ref( $sub ) eq 'CODE' && defined $cron );
    $name = (caller())[0] . "::$name";

    die "Duplicate task name: $name" if( defined $cron->check_entry($name) );

    if( defined $schedule && $schedule !~ /\s/ ) {
	# Single word, fetch a preference for the schedule

	my $sched = Foswiki::Func::getPreferencesValue( $schedule );
	die( "Missing schedule preference: $sched" ) unless( defined $sched );
	$schedule = $sched;
    }
    $schedule = $Foswiki::cfg{CleanupSchedule} || '0 0 * * 0' unless( defined $schedule );

    main::cronlog( main::INFO, "AddTask: $schedule $name( " . join( ',', @_ ) . ' )' );

    # Undocumented: Return task number for debugging

    return $cron->add_entry( $schedule, { subroutine => $sub,
					  args => [ $name,
						    $Foswiki::Plugins::SESSION,
						    @_ ],
					 } );
}

# Add forking task to schedule
#
# Task will be run in its own fork

sub AddAsyncTask {
    my $name = shift;   # Task name (used for logging and to delete task)
                        # Must be unique
    my $sub = shift;    # Subroutine containing task
                        # ( $name, $session, @args )
    my $schedule = shift; # crontab format schedule  (vixiecron + optional seconds col)
                          # or preference name containing one
                          # Default is standard tick schedule

    return AddTask( $name, \&main::ForkTask, $schedule, @_, $sub );
}

# Remove a task from the schedule

sub DeleteTask {
    my $name = shift;

    $name = (caller())[0] . "::$name";

    my $cron = $main::cronhandle;

    my $idx = $cron->check_entry( $name );

    unless( defined $idx && defined $cron->delete_entry( $idx ) ) {
	main::cronlog( main::INFO, "DeleteTask: $name failed" );
	return 0;
    }

    main::cronlog( main::INFO, "DeleteTask: $name succeeded" );

    return 1;
}

# Return next execution time for a task

sub NextRuntime {
    my $name = shift;

    $name = (caller())[0] . "::$name" unless( $name =~/::/ );

    my $cron = $main::cronhandle;

    my $idx = $cron->check_entry( $name );

    return 0 unless( defined $idx );

    my $qe = $cron->get_entry( $idx );
    return 0 unless( defined $qe );

    my $next = $cron->get_next_execution_time( $qe->{time}, 0 );

    return $next || 0;  # Don't return undef
}

# Replace task schedule

sub ReplaceSchedule {
    my $name = shift;
    my $schedule = shift;

    $name = (caller())[0] . "::$name";

    if( defined $schedule && $schedule !~ /\s/ ) {
	# Single word, fetch a preference for the schedule

	my $sched = Foswiki::Func::getPreferencesValue( $schedule );
	die( "Missing schedule preference: $sched" ) unless( defined $sched );
	$schedule = $sched;
    }
    $schedule = $Foswiki::cfg{CleanupSchedule} || '0 0 * * 0' unless( defined $schedule );

    my $cron = $main::cronhandle;

    my $idx = $cron->check_entry( $name );

    my $qe;
    unless( defined $idx && defined( $qe = $cron->get_entry( $idx ) ) ) {
	main::cronlog( main::INFO, "ReplaceSchedule $name failed: task not found" );
	return 0;
    }

    $qe->{time} = $schedule;

    unless( defined $cron->update_entry( $idx, $qe ) ) {
	main::cronlog( main::INFO, "ReplaceSchedule $name failed: internal error" );
	return 0;
    }

    main::cronlog( main::INFO, "ReplaceSchedule: New schedule for $name: $schedule" );

    return 1;
}

# Register interest in configuration item changes
#
# If the TWiki configuration file changes monitored items
# the caller will receive notification.  The registered
# routine can update task schedules, delete or add a task,
# or do something completely unrelated like write umask or enable a signal.
#
# This is only necessary if you cache an item's value in
# some way, such as using it as a schedule or calling a system service
# with it.
#
# You don't need to do this if you simply read a config
# item from Foswiki::cfg every time you need it.
#
# Only one registration per calling package is permitted, but any number of variables can be monitored.
# (More than one will replace previous registration, as will an empty list.)
#
# Changes are detected once in a while; don't count on
# instantaneous notification.

sub RegisterConfigChangeHandler {
    my $items = shift;       # Item name or ref to a list of configuration item names.
                             # e.g. [ '{Plugins}{Me}{MySchedule}', '{Plugins}{Me}{MyFile}', '{Plugins}{Me}{Debug}']
    my $sub = shift;         # Subroutine reference to be called on change
                             # Will be called with: ($session, { item => newval, ... } for items that changed, user arglist)
    my @args = @_;           # Argument list for subroutine.

    $items = [ $items ] unless( ref( $items ) );
                             # Allow a single item to be passed as a variable or string
    return 0 unless( ref( $items ) eq 'ARRAY' && ref( $sub ) eq 'CODE' );

    my $caller = (caller())[0];

    # If nothing to monitor, just remove any previous registration
    unless( @$items ) {
	delete $main::cfgModRegistry{$caller};
	return 1;
    }

    # Just out of paranoia, delete any duplicates
    # Make sure the items at least have reasonable syntax:
    #  {key}{subkey}...

    my( @items, %f);

    foreach my $item (@$items) {
	return 0 if( $item !~ m/^(?:\{[-\w'"]+\})+$/ );
	push @items, $item unless( $f{$item}++ );
    }

    $main::cfgModRegistry{$caller} = {
				      items => [ @items ],
				      sub => $sub,
				      args => [ @_ ],
				     };

    return 1;
}
package main;
######################################################################

sub statusText {

    my $msg = "Job queue:\n";

    my $cron = $cronhandle;

    foreach my $qe ( $cron->list_entries() ) {
	my $job = $cron->check_entry( $qe->{args}->[0] );
	$job = '???' unless( defined $job );
	$msg .= sprintf( "Job %-4s ", $job );
	$msg .= $qe->{time} . ' Next: ' .
	        (scalar localtime( $cron->get_next_execution_time( $qe->{time}, 0 ) )) . ' ' .
		' - ' . $qe->{args}->[0]; # Task name

	my @uargs = @{$qe->{args}};
	$msg .= ' (';
	my @targs = ( 'session' );
	foreach my $arg ( @uargs[2..$#uargs] ) {
	    push @targs, "$arg";
	}
	$msg .= join( ', ', @targs ) . ")\n";
    }
    $msg .= "End of job queue\n";
    return $msg;
}

# Report status to debug file

sub sigHUP {
    # Trip the debugger (if loaded)

    # Write queue to debug file
    logLines( "Periodic Task[$$]I): ", statusText(), \&Foswiki::Func::writeDebug );
}

# Print status on terminal for ^C

sub sigINT {
    if( $debug ) {
	print "Exiting.  Event queue:\n";
	logLines( "\t", statusText(), \&tprint );
    }
#### **kill kids
    exit 1;
}

# Exit - not very gracefully

sub sigTERM {

    unlink( $opts{p} );
#### **kill kids
    # If we're debugging, we're not a daemon (usually)

    Foswiki::Func::writeDebug( "Periodic Task[$$]: Daemon stopped by signal" ) if( $debug );

    exit 0;
}

# Usage

sub HELP_MESSAGE {
    my( $ofh, $optpkg, $optver, $sws ) = @_;

    my $pname = basename $0;

    print $ofh <<"USAGE" ;
$pname runs periodic events for the TWiki subsystem.

Usage:
  $pname options command

Options:
  --help    - print usage summary
  -d        - enable debugging messages
  -v        - Logging level: -1 very verbose, 0 debug, 1 warning (Default), 2 error only
  -f        - Run in foreground
  -l        - don't run login cleanup
  -x        - don't run expired lease cleanup
  -p:file   - write pid to specified file, normally working directory

In normal use, no options are required; these are primarily for debugging.

$pname can be linked as a startup script, enabling the daemon
to startup (and shut down) automatically with the system.

$pname can also be run as a cron job, which simply does a condstart.

Note that the cronjob is exactly compatible with the former tick_twiki
script; previously existing crontabs do not need to be modified.

Commands:
  condstart   - Start the daemon if it is not already running.
                This is the default command.
  start       - Start the daemon
  status      - Display the daemon status.
  status dump - Display status and dump state to TWiki debug log
  stop        - Stop the daemon
  restart     - Stop and re-start the daemon (assumed running)
  condrestart - Stop and re-start the daemon only if it is running

Files:
  /etc/init.d/$pname is a softlink to this script
  $0_bin is a softlink to the TWiki binary directory ($bindir)
  $bindir/setlib.cfg  Defines twiki environment
  $Foswiki::cfg{DataDir} contains standard log files
  $opts{p}/tick_daemon.pid ( or -p )
              pid of daemon

Special considerations:

If you run multiple TWikis from the same webserver, you need multiple daemons.
To set this up:
    /etc/init.d/wikistart is softlinked to $0 (this)
    $0_bin is a softlink to $bindir

    For second wiki
      hardlink $0 to another name, say $0_2.
      softlink /etc/init.d/${pname}_2 to $0_2
      softlink $0_2_bin to other wiki's bin directory

    Additional wikis follow the same pattern.  It is critical that a
    hardlink is used where specified.  If not supported by your system, 
    make a second copy of $0.  A softlink will not work.
USAGE

    return 1;
}

# Logging inteceptor for STDERR (and warn, and unhandled die)

package Foswiki::STDERR;

# tie *STDERR, (*LOGFILE), sub { my $string = shift; do the logging }
#
sub TIEHANDLE {
    my $this = {};

    if ( 'GLOB' eq ref($_[0]) ) {
	$this->{fh} = shift; # Specify actual log file handle if need misc IO functions to work.
    }

    my $class = shift;

    $this->{printsub} = shift or die "No printsub specified in tie";

    # Intercept die and warn, which don't use the STDERR glob

    $this->{'oldwarn'} = $SIG{__WARN__};
    $this->{'olddie'}  = $SIG{__DIE__};
    $SIG{__WARN__} = sub { print STDERR @_; };
    $SIG{__DIE__} = sub {
	                   return if $^S; # In an eval
			   print STDERR @_;
		        };

    return bless( $this, $class );
}

sub PRINT {
    my $this = shift;

    return $this->{printsub}(@_);
}

sub PRINTF {
    my $this = shift;

    $this->PRINT( sprintf( @_ ) );
}

sub FILENO {
    my $this = shift;

    if ( exists($this->{fh}) ) {
	return fileno($this->{fh});
    }
    return undef;
}

sub EOF {
    my $this = shift;

    if ( exists($this->{fh}) ) {
	return eof($this->{fh});
    }
    return undef;
}

sub BINMODE {
    my $this = shift;

    if ( exists($this->{fh}) ) {
	return binmode($this->{fh});
    }
    return undef;
}

sub TELL {
    my $this = shift;

    if ( exists($this->{fh}) ) {
	return tell($this->{fh});
    }
    return undef;
}

sub DESTROY {
    my $this = shift;

    ## restore signal handlers
    {
	local $^W = 0;
	$SIG{__WARN__} = $this->{'oldwarn'};
	$SIG{__DIE__}  = $this->{'olddie'};
    }
    undef $this;
}
package main;

__END__

# TWiki Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2005-2007 TWiki Contributors.
# All Rights Reserved. TWiki Contributors are listed in
# the AUTHORS file in the root of this distribution.
# NOTE: Please extend that file, not this notice.
#
# For licensing info read license.txt file in the TWiki root.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details, published at 
# http://www.gnu.org/copyleft/gpl.html
#
# Timed event daemon for TWiki
