# -*- mode: CPerl; -*-
# TWiki off-line task management framework addon for the TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2011 Timothe Litt <litt at acm dot org>
# License is at end of module.
# Removal of Copyright and/or License prohibited.


use strict;
use warnings;


=pod

---+ package TWiki::Tasks::Execute::Rpc
Remote Procedure Call client for the TASK daemon

Most tasks execute as child forks of the daemon.

The forks request daemon services using the RPC mechanism.  This is the client (fork) side of the protocol.

The public method in this module are called by the API and the daemon internals.  Nothing here is intended for
general use.

This protocol runs on a socketpair created before the fork occurs.  Generally, operation of the protocol - including
calls to this module - are hidden from the user by the API.  The client side of the protocol is synchronous.

The protocol is a simple request/response protocol.  The client requests that a daemon routine be called, and its
arguments are marshalled and sent with the request.  Class, object and static method calls are supported.

Arguments and return values are passed usng Storable, which imposes some restrictions on what can be sent.
See perldoc Storable for the limitations - they don't impact current uses.

The connection is considered secure because the daemon creates the socketpair, the client file descriptor is
inherited by the fork, and the fork contents are specified by a trusted administrator.

This module appears in client tasks, and minimizes the number of external modules that it requires.

ApiServer.pm contains the server side of this protocol.

=cut

package TWiki::Tasks::Execute::Rpc;

use base 'Exporter';
our @EXPORT_OK = qw/rpCall/;

# Do not use any module unless it should appear in an external task

# Suppress traceback from internal calls:
our @CARP_NOT = qw/TWiki::Func TWiki::Tasks TWiki::Tasks::Execute::RpcHandle/;

use Carp;
use Fcntl qw/F_GETFD F_SETFD FD_CLOEXEC/;
use IO::Socket::UNIX;
use Socket qw/:crlf/;
use Storable qw/freeze thaw/;
$Storable::Deparse = 1;
$Storable::Eval = 1;

our $forkedTask;
our $forkedTaskApiSock;

# Initialization
#
# If in an external task, find the protocol FD and materialize a socket for it.
#
# In Daemon context, $forkedTask is an alias of the daemon global.
#
# In an external task, it's a local imitation.

if( exists $ENV{TWikiTaskAPI} ) {
    $forkedTask = 3;
    my $sock = IO::Socket::UNIX->new_from_fd( $ENV{TWikiTaskAPI}, '+<' ) or
      confess "Can't open API socket: $!\n";

    my $f = fcntl( $sock, F_GETFD, 0 ) or confess "fcntl: $!\n";
    fcntl( $sock, F_SETFD, $f & ~FD_CLOEXEC ) or confess "Fcntl: $!\n";

    # new_from_fd does not set autoflush
    $sock->autoflush(1);

    $forkedTaskApiSock = $sock;
} else {
    # Hopefully a fork of the daemon - if an external task not under its control, will
    # fail as this is not supported due to the security complications it would create.

    no warnings 'redefine';
    *forkedTask = \$TWiki::Tasks::Globals::forkedTask;
}

=pod

---++ StaticMethod rpCall( $op, @args ) -> retval
Makes a remote procedure call and returns the value
   * =$op= - Subroutine name ('foo'), class method ('FOO->bar'), or object method (fizz;)
   * =@args= - Argument list for the remote subroutine

The remote procedure will be called in void, array, or scalar context according to the caller of the caller of rpCall, which is
always an API wrapper.

Any exception generated by the remote procedure is reflected to the caller.

Exceptions can also be raised if Storable can't handle the argument list and for I/O errors on the communication path to the
daemon.

Returns whatever the remote routine returns, except that daemon objects have been mapped to RPC handles.  See RpcHandle.pm.

rpCall can only be called in a child fork.

=cut

sub rpCall {
    my $op = shift;

    local $!;
    my $AT = $@;
    $@ = '';

    croak "Improper rpc from daemon context: $op\n" unless( $forkedTask );

    my $sock = $forkedTaskApiSock;

    # rpCall is always implementing the caller's function.
    # Pass on the caller's wantarray (array, scalar or void)

    my $wantarray =  (caller(1))[5];
    if( $wantarray ) {
	$op = "\@$op";
    } elsif( defined $wantarray ) {
	$op = "0$op";
    }

    # Marshall arguments and send
    #
    # Request  is length & opcode, then argument array blob
    # opcode is either a simple subroutine name 'foo', a class method call 'FOO->bar', or an instance method-name suffixed with ';' 'foo;'
    # The latter indicates that the invocant is an rpc object and 
    # that the real object needs to be substituted.  (This form
    # is automagically generated by AUTOLOAD)
    # In either case, if the subname is prefixed by @, the call is in list context, or 0 is scalar context.

    # Both Storable and I/O can raise exceptions

    eval {
	local $.;
	my $args;

	defined( $args = freeze( \@_ ) ) or
	  die "Failed to serialize arglist\n";

	print $sock length( $args ), " $op$LF", $args or
	  die "Write failure:$!\n";
    };
    if( $@ ) {
	chomp $@;
	croak "RPC send for $op failed: $@\n";
    }

    # Read response record

    my( $rop, $rval );
    eval {
	local $/ = $LF;
	local $.;

	defined( $rval = readline( $sock ) ) or
	  die "Read failure: $!\n";

	my $rlen;
	(($rlen, $rop ) = $rval =~ /^(\d+) (.*)$/) && $rlen > 0 or
	  die "Invalid response: $rval\n";

	# Unmarshall value, which always results in a REF

	my $rn = read( $sock, $rval, $rlen );
	defined( $rn ) or
	  die "Read failure: $!\n";
	$rn == $rlen or
	  die "Invalid response: $rn";

	$rval = thaw( $rval ) or
	  die "Failed to deserialize response\n";
    };
    if( $@ ) {
	chomp $@;
	croak "RPC receive for $op failed: $@\n";
    }

    # Reflect any exception incurred in server context

    if( $rop =~ /^_RpcDied_/ ) {
	croak $$rval;
    }

    # Restore caller's $@ now that no exception is possible

    $@ = $AT;

    # Return value

    return @$rval if( ref $rval eq 'ARRAY' );
    return $$rval if( ref $rval eq 'SCALAR' );
    return %$rval if( ref $rval eq 'HASH' );

    # Globs aren't supported.

    return $$rval;
}

1;

__END__

This is an original work by Timothe Litt.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 3
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details, published at
http://www.gnu.org/copyleft/gpl.html
