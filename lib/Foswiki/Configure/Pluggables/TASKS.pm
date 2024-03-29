# -*- mode: CPerl; -*-
# TWiki off-line task management framework addon for the TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2011 Timothe Litt <litt at acm dot org>
# License is at end of module.
# Removal of Copyright and/or License prohibited.


use warnings;
use strict;


=pod

---+ package Foswiki::Configure::TASKS
Plug-in module for finding and handling external (non-plugin) task drivers

=cut


package Foswiki::Configure::Pluggables::TASKS;
use Carp; # work-around for missing use Carp in Configure::Section
          # This is here so all TFW modules can be independently 
          # compiled/syntax-checked.
use base 'Foswiki::Configure::Pluggable';


use Foswiki::Configure::Pluggable;
use Foswiki::Configure::Section;
use Foswiki::Configure::Type;
use Foswiki::Configure::Value;
use Foswiki::Configure::FoswikiCfg;
use Foswiki::Configure::Item;

my $scanner = Foswiki::Configure::Type::load('SELECTCLASS');

sub new {
    my ($class) = @_;

    my $this = $class->SUPER::new('Installed Task Drivers');
    my %modules;
    my $classes = $scanner->findClasses('Foswiki::Tasks::Tasks::*Task');
    foreach my $module ( @$classes ) {
        my $mod = $module;
	$mod =~ s/^.*::([^:]*)/$1/;
        # only add the first instance of any driver, as only
        # the first can get loaded from @INC.
        $modules{$mod} = $module;
    }
    foreach my $mod (sort { lc $a cmp lc $b } keys %modules) {
	my $module = $modules{$mod};
	eval "require $module;"; die "$module: $@\n" if( $@ );
	my $desc = "${module}::DESCRIPTION";
	no strict 'refs';
	my @desc = ( desc => $$desc ) if( defined $$desc );
	use strict 'refs';

	my $file = $module;
	$file =~ s!::!/!g;
	$file = $INC{$file . '.pm'};
	$file =~ s/.pm$/.spec/;
	unless( -e $file ) {
	    $this->addChild(
			    new Foswiki::Configure::Value('BOOLEAN',
				  parent=>$this,
				  keys => '{Tasks}{Tasks}{'.$mod.'}{Enabled}',
				  @desc,
				  ));
	    next;
	}

	# Because Configure::Load can't find these files, they
	# won't be in the defaults hash.  We'll make that happen
	# here rather than have Load do yet another disk scan by
	# class.

	eval {
	    require Hash::Merge;
	    local %Foswiki::cfg = ();
	    do $file;
	    # Keys just read are new defaults, but we must merge into any existing keys.
	    # E.g. if {a}{b} = x exists, adding {a}{c} = y must preserve {b} (and all other data in {a}.

	    my $merge = Hash::Merge->new( 'LEFT_PRECEDENT' );
	    $Foswiki::defaultCfg = $merge->merge( $Foswiki::defaultCfg, \$Foswiki::cfg );
	};
	die "Unable to parse $file:$@\n" if( $@ );

	open( my $spec, '<', $file ) or next;
	$desc = '';
	$desc = "<span style=\"font-family:monospace;\">$file</span><hr />"
	      if( 0 && CGI::param( 'expert') );

	my $open =  new SectionMarker( 0, (@desc? $desc[1] : "$mod Interface module")  );
	my @settings;

	while( (my $l = <$spec>) ) {
	    if( $l =~ /^#\s*\*\*\s*([A-Z]+)\s*(.*?)\s*\*\*\s*$/ ) {
		# ** TYPENAME Options **
		my( $typename, $options ) = ($1, $2);
		Foswiki::Configure::FoswikiCfg::_pusht(\@settings, $open) if $open;
		$open = new Foswiki::Configure::Value($typename, opts=>$options, );
		if( length( $desc ) ) {
		    $open->set('desc', $desc );
		    $desc = '';
		}
	    } elsif ($l =~ /^#?\s*\$(Foswiki::)?cfg([^=\s]*)\s*=/) {
		#? $Foswiki::cfg{keys} =
		my $keys = $2;
		if ($open && $open->isa('SectionMarker')) {
		    Foswiki::Configure::FoswikiCfg::_pusht(\@settings, $open);
		    $open = undef;
		}
		# If there is already a UI object for
		# these keys, we don't need to add another. But if there
		# isn't, we do.  We don't have the root, but we can at least
		# check what we're adding.
		if (!$open) {
		    next if $this->getValueObject($keys);
		    next if (Foswiki::Configure::FoswikiCfg::_getValueObject($keys, \@settings));
		    # This is an untyped value
		    $open = new Foswiki::Configure::Value();
		    if( length( $desc ) ) {
			$open->set('desc', $desc );
			$desc = '';
		    }
		}
		$open->set(keys => $keys);
		Foswiki::Configure::FoswikiCfg::_pusht(\@settings, $open);
		$open = undef;
	    } elsif( $l =~ /^#\s*\*([A-Z]+)\*/ ) {
		# * PLUGIN
		# Shouldn't be used in these files - it's how we get here
		my $pluggable = $1;
		my $p = Foswiki::Configure::Pluggable::load($pluggable);
		if ($p) {
		    Foswiki::Configure::FoswikiCfg::_pusht(\@settings, $open) if $open;
		    $open = $p;
		} elsif ($open) {
		    $l =~ s/^#\s?//;
		    $open->addToDesc($l);
		}
	    } elsif( $l =~ /^#\s*---\+(\+*) *(.*?)$/ ) {
		# *---+ SectionName
		my( $depth, $name ) = ( $1, $2 );
		Foswiki::Configure::FoswikiCfg::_pusht(\@settings, $open) if( $open );
		$open = new SectionMarker(length($depth)+1, $name, );
		if( length( $desc ) ) {
		    $open->set('desc', $desc );
		    $desc = '';
		}
	    } elsif( $l =~ /^#\s?(.*)$/ ) {
		# description
		$open->addToDesc($1) if $open;
	    }
	}
	close($spec);
	Foswiki::Configure::FoswikiCfg::_pusht(\@settings, $open) if $open;
	@settings = ( $settings[0], 
		      new Foswiki::Configure::Value('BOOLEAN',
				keys => '{Tasks}{Tasks}{'.$mod.'}{Enabled}'),
		      @settings[1..$#settings],
		    );
	Foswiki::Configure::FoswikiCfg::_extractSections(\@settings, $this );
    }
    return $this;
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
