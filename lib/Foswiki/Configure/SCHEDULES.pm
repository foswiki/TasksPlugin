#
# Copyright (c) 2011 Timothe Litt <litt at acm dot org>
#
# Full notice at end of file.

package TWiki::Configure::SCHEDULES;

use strict;

use TWiki::Configure::TWikiCfg;
use TWiki::Configure::Section;
use TWiki::Configure::Value;
use TWiki::Configure::Pluggable;
use TWiki::Configure::Item;

use base 'TWiki::Configure::Pluggable';

use CGI;
use Error;
use File::Basename;

# This is a nonstandard (I think) usage of the pluggable extension mechanism.
#
# The mechanism is normally used for things like LANGUAGES to offer choices
# based on what's installed.
#
# The trick here is to make it possible for all the SCHEDULE-related items to live
# in the same section, but not require each plugin/extension to modify a single
# .spec file.  
#
# The approach is that lib/TWiki/Contrib/PeriodicTasks/Config.spec contains the
# scheduling configuration for built-in tasks.
#
# It calls for the magical SCHEDULES pluggable at the end, which causes this
# class to be instantiated.  Here, we use some slight of hand to find the
# Config.spec file, and then scan its directory for all other .spec files.
#
# Files found are processed into a sub-section of the Periodic Tasks section.
#
# The algorithm is very similar to TWikiCfg.pm;s _loadSpecsFrom routine.
# So similar that I call a couple of private routines rather than copy
# them here.
#
# This could be done better with a few changes to the architecture, but
# at this time, the goal is not to modify the core.  So we'll live with
# the slight oddities (such as appearing to be one level too deep).
# 
# The main issue is that we don't have the real root of the GUI structure
# available.  We also have to return something, so if there are no
# add-on spec files, we can't suppress the heading.  Oh, well.

sub new {
    my ($class) = @_;

    # This becomes a sub-section header for whatever we find.

    my $this = $class->SUPER::new('Add-on Periodic Tasks');

    # Use location of containing .spec file to find more schedules.
    # As there isn't a formal method, consult %INC.

    my( $dir, $sfile );
    foreach  my $rf (keys %INC) {
	if( $rf =~ m !^(.*/Contrib/PeriodicTasks)/(Config.spec)$! ) {
	    $rf = $INC{$rf};
	    $dir = dirname( $rf );
	    $sfile = basename( $rf );
	    last;
	}
    }
    return $this unless( $dir && length $dir );

    opendir( my $dh, $dir ) or
      return $this;

    foreach my $file ( sort readdir $dh ) {
        next unless( $file =~ m/^(.*)\.spec$/ && $file ne $sfile );
        my $addon = $1;

	open( my $aos, '<', "$dir/$file" ) or next;
	my $desc = '';
	$desc = "<span style=\"font-family:monospace;\">$dir/$file</span><hr />"
	      if( CGI::param( 'expert') );
	my $open = undef;
	my @settings;

	while( (my $l = <$aos>) ) {
	    if( $l =~ /^#\s*\*\*\s*([A-Z]+)\s*(.*?)\s*\*\*\s*$/ ) {
		# ** TYPENAME Options **
		my( $typename, $options ) = ($1, $2);
		TWiki::Configure::TWikiCfg::pusht(\@settings, $open) if $open;
		$open = new TWiki::Configure::Value(typename=>$typename, opts=>$options, parent=>$this );
		if( length( $desc ) ) {
		    $open->set('desc', $desc );
		    $desc = '';
		}
	    } elsif ($l =~ /^#?\s*\$(TWiki::)?cfg([^=\s]*)\s*=/) {
		#? $TWiki::cfg{keys} =
		my $keys = $2;
		if ($open && $open->isa('SectionMarker')) {
		    TWiki::Configure::TWikiCfg::pusht(\@settings, $open);
		    $open = undef;
		}
		# If there is already a UI object for
		# these keys, we don't need to add another. But if there
		# isn't, we do.  We don't have the root, but we can at least
		# check what we're adding.
		if (!$open) {
		    next if $this->getValueObject($keys);
		    next if (TWiki::Configure::TWikiCfg::_getValueObject($keys, \@settings));
		    # This is an untyped value
		    $open = new TWiki::Configure::Value();
		    if( length( $desc ) ) {
			$open->set('desc', $desc );
			$desc = '';
		    }
		}
		$open->set(keys => $keys);
		TWiki::Configure::TWikiCfg::pusht(\@settings, $open);
		$open = undef;
	    } elsif( $l =~ /^#\s*\*([A-Z]+)\*/ ) {
		# * PLUGIN
		# Shouldn't be used in these files - it's how we get here
		my $pluggable = $1;
		my $p = TWiki::Configure::Pluggable::load($pluggable);
		if ($p) {
		    TWiki::Configure::TWikiCfg::pusht(\@settings, $open) if $open;
		    $open = $p;
		} elsif ($open) {
		    $l =~ s/^#\s?//;
		    $open->addToDesc($l);
		}
	    } elsif( $l =~ /^#\s*---\+(\+*) *(.*?)$/ ) {
		# *---+ SectionName
		my( $depth, $name ) = ( $1, $2 );
		pushd(\@settings, $open) if( $open );
		$open = new SectionMarker(length($depth), $name, parent => $this);
		if( length( $desc ) ) {
		    $open->set('desc', $desc );
		    $desc = '';
		}
	    } elsif( $l =~ /^#\s?(.*)$/ ) {
		# description
		$open->addToDesc($1) if $open;
	    }
	}
	close($aos);
	TWiki::Configure::TWikiCfg::pusht(\@settings, $open) if $open;
	TWiki::Configure::TWikiCfg::_extractSections(\@settings, $this );
    }
    closedir( $dh );
    return $this;
}

1;
__END__

# TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2000-2011 TWiki Contributors.
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
# As per the GPL, removal of this notice is prohibited.
