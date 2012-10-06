# Plugin for TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2000-2003 Andrea Sterbini, a.sterbini@flashnet.it
# Copyright (C) 2001-2006 Peter Thoeny, peter@thoeny.org
# and TWiki Contributors. All Rights Reserved. TWiki Contributors
# are listed in the AUTHORS file in the root of this distribution.
# NOTE: Please extend that file, not this notice.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of this distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# For licensing info read LICENSE file in the TWiki root.

=pod

---+ package PeriodicTestPlugin

Plugin used to test the Periodic Events Daemon

=cut

package TWiki::Plugins::PeriodicTestPlugin;

# Always use strict to enforce variable scoping
use strict;

require TWiki::Func;    # The plugins API
require TWiki::Plugins; # For the API version

use vars qw( $VERSION $RELEASE $SHORTDESCRIPTION $debug $pluginName $NO_PREFS_IN_TOPIC );

# This should always be $Rev: 15942 (11 Aug 2008) $ so that TWiki can determine the checked-in
# status of the plugin. It is used by the build automation tools, so
# you should leave it alone.
$VERSION = '$Rev: 15942 (11 Aug 2008) $';

$RELEASE = 'V0.000-001';

$SHORTDESCRIPTION = 'Plugin used for testing periodic event mechanism';

$NO_PREFS_IN_TOPIC = 1;
$pluginName = 'PeriodicTestPlugin';

=pod

---++ initPlugin($topic, $web, $user, $installWeb) -> $boolean
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
   * =$user= - the login name of the user
   * =$installWeb= - the name of the web the plugin is installed in

=cut

sub initPlugin {
    my( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if( $TWiki::Plugins::VERSION < 1.026 ) {
        TWiki::Func::writeWarning( "Version mismatch between $pluginName and Plugins.pm" );
        return 0;
    }

#    TWiki::Func::registerTagHandler( 'EXAMPLETAG', \&_EXAMPLETAG );

    # The following is only necessary if you have periodic tasks that you want to run on a
    # non-default schedule and/or as independent forks.
    #
    # The schedule is the time portion of a crontab entry - with the vixiecron extensions.
    # The 6th column is optional, and means seconds.
    #
    # Minute 0-60, hour 0-23, day-of-month 1-31, month (1-12,names), day-of-week (0/7=sun, names), Seconds (0-59)
    #
    # We recomend that you make the schedule a configuration item - configure will provide a sensible GUI and
    # validate the syntax.
    #
    # Register periodic tasks if we are running in the daemon.  These APIs don't exist in the webserver.

    if( TWiki::Func::getContext()->{Periodic_Task} ) {

	# A standard synchronous task with a programable schedule

	TWiki::Func::AddTask( 'cronTask1',  # task name
				  \&cronTask,   # Subroutine to run
				  $TWiki::cfg{Plugins}{$pluginName}{Schedule}, # Schedule in crontab format
				                # May also be undef for the default plugin cleanup schedule
				                # or a preference name
				  1, 4, 19,     # Arguments for routine
				);

	# This schedules an asynchronous task - presumably because it runs for a long time.

	TWiki::Func::AddAsyncTask( 'Mail',  # task name
				  \&cronTask,   # Subroutine to run
				  $TWiki::cfg{MailerSchedule}, # Schedule in crontab format
				                # May also be undef for the default plugin cleanup schedule
				                # or a preference name
				  "runmail", "Mailer.Log",     # Arguments for routine
				);

	# Another synchronous task

	TWiki::Func::AddTask( 'News',  # task name
				  \&cronTask,   # Subroutine to run
				  "18 20 * Jul-Sep Sun,Sat", # Schedule in crontab format
				                # May also be undef for the default plugin cleanup schedule
				                # or a preference name
				  "runnews", "News.Log",     # Arguments for routine
				);

	# A couple more asynchronous tasks on the same schedule.
	# You can see (and kill) these with ps and kill to see what happens.

	TWiki::Func::AddAsyncTask( 'Forker-1', \&forktest, "*/2 * * * * 23", 'p1', 'p2' );
	TWiki::Func::AddAsyncTask( 'Forker-2', \&forktest, "*/2 * * * * 23", 'p1', 'p2' );

	# Because the daemon is a persistent environment, you may be sensitive to configuration
	# changes.  TWiki::cfg is always up-to-date (after some delay), but if you have 
	# cached a value, you need to update your cache with the latest value(s).
	#
	# This is an issue for schedules (because they were passed to the DAEMON, for
	# values you write to disk or pass to other system services.
	#
	# To handle this, simply register a handler to be called when the configuration
	# items that you are interested in change.  That handler will be called with the
	# session reference, a reference to a hash of variable => new value, and any other
	# arguments provided at registration.
	#
	# Specify your item as '{ItemName}' as you would see it in the configure screen.
	# If you have more than one, pass a reference to an array of names.
	#
	# For example, here we register to handle schedule changes and a service enable

#	RegisterConfigChangeHandler( '{CleanupSchedule}', \&reconfigHandler, 'Foo' );

	TWiki::Func::RegisterConfigChangeHandler( [ '{Plugins}{$pluginName}{Schedule}',
						    '{CleanupSchedule}',
						    '{MailerSchedule}',
						    '{EnableMailer}',
						  ], \&reconfigHandler );

    }

    # Plugin correctly initialized
    return 1;
}

# Task run on specified schedule
#
# You can have as many of these tasks as you like, and a given subroutine can
# be scheduled by any number of task entries.  However, each $name must be unique 
# in this plugin.  (Names are qualfied by __PACKAGE__)
#
# A name may not contain ::.
#
# This routine just logs its execution and arguments to demonstrate that the schedule works.

sub cronTask {
    my( $name, $session, $arg1, $arg2, $arg3 ) = @_;

    TWiki::Func::writeDebug( "$pluginName: $name: cronTask( $arg1, $arg2, $arg3 )" );

    TWiki::Func::writeDebug( "$name - Nextrun " . (scalar localtime( TWiki::Func::NextRuntime( $name ) )) );
    TWiki::Func::writeDebug( "Forker-1 - Nextrun " . (scalar localtime( TWiki::Func::NextRuntime( 'TWiki::Periodic::Forker-1' ) )) );

    # Always return success (like a command)
    return 0;
}

# Scheduled task that runs as a separate fork - but inheriting a copy of the session

sub forktest {
    my( $name, $twiki, @args ) = @_;

    # This will be logged to the error file
    # Note that any external command (system, backticks, fork) will usually see /dev/null

    print STDERR "Forktest-$name\[$$] stderr message: (", join( ', ', @args ), ")\n";

    # Verify that TWiki API is active

    TWiki::Func::writeDebug( "$name: " . TWiki::Func::getScriptUrl('Main', 'WebHome', 'view', p1=>'cat', p2 => '&', p3 => 'mouse' ) );

    TWiki::Func::writeWarning( "$name: " . "Webs in danger: " . join( ', ', TWiki::Func::getListOfWebs("user,public,allowed") ) );

    my( $meta, $text ) = TWiki::Func::readTopic( "Main", "WebHome" );
    TWiki::Func::writeDebug( "$name: " . 'Yea: ' . join( "\\n", ((split( /\n+/, $text, 3) )[0..1]) ) . ' verily' );

    # Sleep long enough for ps to verify that we are running independently
    # Also long enough for a manual kill -TERM (to verify that's reported properly)

    sleep 60;

    return ($name eq 'TWiki::Periodic::Forker-1'? 47 : 0);
}

# Handler for reconfiguration events.
#
# Propagate changes in monitored configuration items to consumers.
#
# Runs only in the main Daemon, not in any asynchronous tasks.
#
# Note that a change is signalled when an item is added, removed, or its value changed.
#
# Multiple items can come in one report.  Changes is a hash of new values keyed by name,
# where the name is the %TWiki::cfg hash reference.  E.g. {foo}{bar}
#
# This sample is rather more complex than a typical plugin would need.

sub reconfigHandler {
    my( $twiki, $changes ) = @_;

    foreach my $change (keys %$changes) {
	my $value = $changes->{$change};
	({
	     '{Plugins}{$pluginName}{Schedule}' => sub {
		                                           TWiki::Func::ReplaceSchedule( 'cronTask1', $value );
						       },
	     '{CleanupSchedule}' => sub { # Note this is the default if any other schedule is undefined
		                            TWiki::Func::ReplaceSchedule( 'cronTask1', undef ) unless( defined $TWiki::cfg{Plugins}{$pluginName}{Schedule} );
		                            TWiki::Func::ReplaceSchedule( 'Mail', undef ) unless( defined $TWiki::cfg{MailerSchedule} );

						   },
	     '{MailerSchedule}' => sub {
		                            TWiki::Func::ReplaceSchedule( 'Mail', $value );
					},
	     '{EnableMailer}' => sub {
		                         if( $value ) {
					     TWiki::Func::AddAsyncTask( 'Mail', \&cronTask, $TWiki::cfg{MailerSchedule}, "runmail-async", "Mailer.Log" );
					 } else {
					     TWiki::Func::DeleteTask( 'Mail' );
					 }
				     },
	}->{$change} || sub { })->($change, $value);
    }

    return;
}

# Task run on standard plugin cleanup schedule
#
# You need only define this subroutine for it to be called on the admin-defined schedule
# $TWiki::cfg{CleanupSchedule}
#
# For a simple plugin, this is all you need.  This sample code simply deletes old files
# in the working area.  The age is configured by a web preference or a config item.
#
# This name (pluginCleanup) is required.

sub pluginCleanup {
    my( $session, $now ) = @_;

    TWiki::Func::writeDebug( "$pluginName: Running pluginCleanup: $now" );

    my $wa = TWiki::Func::getWorkArea($pluginName);

    # Maximum age for files before they are deleted.
    # Note that updating MaxAge in configure will be reflected here without any code in the plugin.

    my $maxage =  TWiki::Func::getPreferencesValue( "\U$pluginName\E_MAXAGE" ) ||
                  $TWiki::cfg{Plugins}{$pluginName}{MaxAge} || 24;

    my $oldest = $now - ($maxage*60*60);

    # One might want to select only certain files from the working area and/or log deletions.

    foreach my $wf ( glob( "$wa/*" ) ) {
	my( $uid, $gid, $mtime ) = (stat $wf)[4,5,9];

	if( $uid == $> && $gid == $)+0 && $mtime < $oldest) {
	    $wf =~ /^(.*$)$/;               # Untaint so -T works
	    $wf = $1;
	    unlink $wf or TWiki::Func::writeWarning( "Unable to delete $wa: $!" );
	}
    }

    return 0;
}

#sub _EXAMPLETAG {
#}

=pod

---++ earlyInitPlugin()

This handler is called before any other handler, and before it has been
determined if the plugin is enabled or not. Use it with great care!

If it returns a non-null error string, the plugin will be disabled.

=cut

sub DISABLE_earlyInitPlugin {
    return undef;
}


1;
