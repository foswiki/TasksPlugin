# Copyright (c) 2011 Timothe Litt <litt at acm dot org>
#
# Full notice at end of file

package Foswiki::Configure::Types::SCHEDULE;

use warnings;
use strict;

use base 'Foswiki::Configure::Type';

=pod

GUI module for SCHEDULE variables

This attempts to provide a tolerable GUI for crontab time schedules.
I think this is an improvement over the raw table strings in both
comprehensibility and in error avoidance.  

See lib/TWiki/Contrib/PeriodicTasks/Config.spec for the on-screen
text and variable definitions.

The corresponding checker abstract class is Foswiki::Configure::ScheduleChecker.

Use Twiki::Configure::Checkers::CleanupSchedule as a template for
creating an instance for additional SCHEDULE variables.  Name
yours Foswiki::Configure::Checkers::Plugins::<plugin-name>::<YourSchedule>.pm
It's only a dozen lines of perl, and you only need to change the package
name and the Foswiki::cfg key to customize it.

Loose ends:

o Requires a patch in Foswiki::Configure::Valuer
o We don't currently handle */interval on-screen as I don't have an easy html metaphor.
o There are a couple of hardcoded -styles that a purist might want to css-ify.
  They don't bother me...much.
o It would be nice if plugins requiring schedules had an easy way to add themselves
  to our Config.spec.  Perhaps an Include directory?  That's a configure issue.
  For now, something like this should work:
  grep -q '{Plugins}{FoobazSchedule}' lib/TWiki/Contrib/PeriodicTasks/Config.spec || \
  cat >>lib/TWiki/Contrib/PeriodicTasks/Config.spec <<EOF
# **SCHEDULE**
# Schedule for Foobaz database cleaning service.  Recommended at least twice a week
# even on minimally-used systems.
\$Foswiki::cfg{Plugins}{FoobazSchedule} = '3 13 * * Sun,Wed 0';
EOF

=cut

# Sorting alphas:
my %dayMap = ( 
	      '*' => '*', '_*' => '*',
	      sun => 0, 0 => 0, 7 => 7, _0 => 'sun', _7 => 'sun',
	      mon => 1, 1 => 1, _1 => 'mon',
	      tue => 2, 2 => 2, _2 => 'tue',
	      wed => 3, 3 => 3, _3 => 'wed',
	      thu => 4, 4 => 4, _4 => 'thu',
	      fri => 5, 5 => 5, _5 => 'fri',
	      sat => 6, 6 => 6, _6 => 'sat',
	     );

my %monMap = (
	      '*' => '*', '_*' => '*',
	      jan => 1, 1 => 1, _1 => 'jan',
	      feb => 2, 2 => 2, _2 => 'feb',
	      mar => 3, 3 => 3, _3 => 'mar',
	      apr => 4, 4 => 4, _4 => 'apr',
	      may => 5, 5 => 5, _5 => 'may',
	      jun => 6, 6 => 6, _6 => 'jun',
	      jul => 7, 7 => 7, _7 => 'jul',
	      aug => 8, 8 => 8, _8 => 'aug',
	      sep => 9, 9 => 9, _9 => 'sep',
	      oct => 10, 10 => 10, _10 => 'oct',
	      nov => 11, 11 => 11, _11 => 'nov',
	      dec => 12, 12 => 12, _12 => 'dec',
	     );
my %numMap = (
	      '*' => '*', '_*' => '*',
	      map { ($_ => $_, '_'.$_ => $_) } (0..59),
	     );
my %map = ( %dayMap, %monMap );

#$DB::signal=1;

# Sort a list of cron elements

sub _cronsort {
    return 0 if( $a eq $b );
    return -1 if( $a eq '*' );
    return 1 if( $b eq '*' );
    return $a <=> $b if( $a =~ /^[0-9]+$/ && $b =~ /^[0-9]+$/ );
    my ($ma, $mb) = ( $map{lc $a}, $map{lc $b} );
    return $ma <=> $mb if( defined $ma && defined $mb );
    return $a cmp $b;
}

sub new {
    my ($class, $id) = @_;

    my $self = bless({ name => $id }, $class);

    # Make Valuer.pm call string2value with query and item name
    # This enables us to find all the sub-fields in POST data

    $self->{NeedsQuery} = 1;
    return $self;
}

# Remove duplicate values from a list

sub _remdups {
    my @list = sort _cronsort @_;

    my @out = ();

    @out = shift @list;
    while( @list ) {
	if( lc $out[-1] eq lc $list[0] ) {
	    shift @list;
	} else {
	    push @out, shift( @list );
	}
    }
    return @out;
}

# Expands any ranges and interval repeats found in a cron field & removes duplicates
# Returns value list suitable for generating CGI form boxes

sub _expand {
    my( $map, @list ) = ( $_[0], split( /,/, $_[1] ) );
    my( $min, $max ) = ( @_[2..3] );

    return ( '*', )  unless( @list ); # Empty list?

    my @expanded = ();

    # Scan for ranges and expand
    # Normalize to numeric for duplicate detection

    foreach my $ele (@list) {
	if( $ele =~ m!^(\w+)-(\w+)(?:/(\d+))?$! ) {
	    my $start = $map->{lc $1} || 0;
	    my $end = $map->{lc $2} || 0;
	    my $step = $3 || 1;

	    for( my $v = $start; $v <= $end; $v += $step ) {
		push @expanded, $v;
	    }
	} elsif( $ele =~ m!^\*/(\d+)$! ) {
	    my $step = $1 || 1;

	    for( my $v = $min; $v <= $max; $v += $step ) {
		push @expanded, $v;
	    }

	} elsif( exists $map->{lc $ele} ) {
	    push @expanded, $map->{lc $ele};
	} else {
	    push @expanded, $ele;
	}
    }

    # Remove duplicates and remap to text

    @list = map { ucfirst $map->{'_' . $_} } _remdups( @expanded );

    return @list;
}

# Generate the GUI for this schedule
# Returns HTML

sub prompt {
    my( $this, $id, $opts, $value ) = @_;

    # Generate safe ID for sub-fields of form.
    my $xid = $id;
    $xid =~ tr /\{\}/()/;

    $value = "1 15 1-31/4 * * 15" unless( defined $value );

    # Generate a hidden variable for the actual schedule

    my $boxes = CGI::hidden( -name => $id, -value => $value );

    # Break the value, a crontab string, into 5 or 6 fields

    my @vals = split( /\s/, $value );

    # Build a table to hold headings and pulldown boxes

    $boxes .= CGI::start_table(), CGI::start_Tr();

    # Display the actual crontab string (Is this debug only, or useful?  For now, 'expert' mode.)
    if( CGI::param( 'expert') ) {
	$boxes .= "<h6>Expert</h6><td colspan='6'><b>Crontab:</b> ";
	$boxes .= CGI::textfield( -name => $xid.'Summary', -size=>length($value), 
				  -style=>'font-family:monospace;', 
				  -default=>$value, -readonly => 1 ) . 
		  '</td>';
	$boxes .= CGI::end_Tr(); $boxes .= CGI::start_Tr()
    }

    # Human display order; indexes in @vals are crontab order

    foreach my $field (qw/Days Months Days Hours Minutes Seconds/ ) {
	$boxes .= CGI::td( CGI::b(CGI::u($field)) );
    }
    $boxes .= CGI::end_Tr(); $boxes .= CGI::start_Tr();

    # This shows the raw crontab lists - so it's not necessary to scroll the listboxes for an overview.

    for my $field ( 4, 3, 2, 1, 0, 5 ) {
	$boxes .= CGI::td( $vals[$field] );
    }
    $boxes .= CGI::end_Tr(); $boxes .= CGI::start_Tr( );

    $boxes .= CGI::td( { -style=>'vertical-align:top;' }, 
			CGI::popup_menu( -name => $xid.'dow', -override =>1, 
					-default => [_expand( \%dayMap, $vals[4], 0, 6 )], 
					-values => [qw/* Sun Mon Tue Wed Thu Fri Sat/], 
					-size => 8, -multiple => 1 ) );
    $boxes .= CGI::td( { -style=>'vertical-align:top;' }, 
		       CGI::popup_menu( -name => $xid.'mon', -override =>1, 
					-default => [_expand( \%monMap, $vals[3], 1, 12 )], 
					-values => [qw/* Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec/], 
					-size => 13, -multiple => 1 ) );
    $boxes .= CGI::td( { -style=>'vertical-align:top;' }, 
		       CGI::popup_menu( -name => $xid.'dom', -override =>1, 
					-default => [_expand( \%numMap, $vals[2], 1, 31 )], 
					-values => ['*', 1..31], 
					-size => 16, -multiple => 1 ) );

    $boxes .= CGI::td( { -style=>'vertical-align:top;' }, 
		       CGI::popup_menu( -name => $xid.'hour', -override =>1, 
					-default => [_expand( \%numMap, $vals[1], 0, 23 )], 
					-values => ['*', 0..23], 
					-size => 16, -multiple => 1 ) );
    $boxes .= CGI::td( { -style=>'vertical-align:top;' }, 
		       CGI::popup_menu( -name => $xid.'min', -override =>1, 
					-default => [_expand( \%numMap, $vals[0], 0, 59 )], 
					-values => ['*', 0..59], 
					-size => 16, -multiple => 1 ) );
    $boxes .= CGI::td( { -style=>'vertical-align:top;' }, 
		       CGI::popup_menu( -name => $xid.'sec', -override =>1, 
					-default => [_expand( \%numMap, $vals[5], 0, 59 )], 
					-values => ['*', 0..59], 
					-size => 16, -multiple => 1 ) );

    $boxes .= CGI::end_Tr(); $boxes .= CGI::end_table();

    return $boxes;
}

# Helper for _condense to handle generating */interval or range
# Output is appended to input value.  Text fields are re-mapped from
# numbers to the prefered text.

sub _outrange {
    my( $map, $value, $last, $min, $max ) = @_;

    # Ending long interval, output range (m-n), and if interval isn't 1, /i
    # However, if the range runs from min to max (accounting for interval, which can
    # overhang the useful part of the range), we can use */interval instead.
    #
    # e.g. 1, 3, 5 selected from an item with (min,max) = (1, 6) can be expressed as */2.

    my( $start, $end, $interval ) = ( $last->{start}, $last->{end}, $last->{interval} );

    $value .= ',' if( length $value );
    {
	use integer;

	if( $start <= $min && $end >= ((($max - $start)
							/ $interval) * $interval)
		                      + $start ) {
	    $value .= '*';
	} else {
	    $value .= ucfirst( $map->{'_' . $start } ) . '-' . ucfirst $map->{'_' . $end};
	}
    }
    $value .= '/' . $interval unless( $interval == 1 );

    return $value;
}

# Condense a value list into ranges and return a string usable as a crontab entry field.

sub _condense {
    my( $map, $min, $max, @values ) = ( @_ );

    return '*' unless( @values );

    my $value = '';

    # Sorted list of numeric (or '*') values with no duplicates

    @values = _remdups( map { (exists $map->{lc $_})? $map->{lc $_} : $_ } @values );

    # '*' can only be first, can't be combined so just move to output

    if( $values[0] eq '*' ) {
	$value = '*';
	shift @values;
	return $value unless( @values );
    }

    return '*/1' unless( $values[0] =~ /^\d+$/ ); # Garbage in, * out - /1 is to indicate error for debug

    # Initialize last item/working range with first value

   my $last = {
	       start => $values[0], # Start of interval
	       end => $values[0],   # End of interval
	       interval => 0,       # Interval width
	       n => 1,              # Number of values in the range
	      };
    shift(@values);

    # Build condensed string by merging items into ranges when profitable

    while( my $next = shift @values ) {
	return '*/1' unless( $next =~ /^\d+$/ ); # Garbage in, * out - /1 is to indicate error for debug

	my $gap = $next - $last->{end};
	if( $last->{interval} == 0 ) {
	    # Second element starts a new interval sequence
	    $last->{interval} = $gap;
	    $last->{end} = $next;
	    $last->{n} = 2;
	    next;
	}
	if( $gap == $last->{interval} ) {
	    # Continuing at same interval, update range
	    $last->{end} = $next;
	    $last->{n}++;
	    next;
	}
	if( $last->{n} < 3 ) {
	    # m-n & m-n/i aren't worthwhile.  Dump all but last of old as a list.
	    # The last may work as the start of a new interval sequence.
	    while( $last->{n} > 1 ) {
		$value .= ',' if( length $value );
		$value .= ucfirst $map->{'_' . $last->{start}};
		$last ->{start} += $last->{interval};
		$last->{n}--;
	    }
	    $last->{interval} = $gap;
	    $last->{end} = $next;
	    $last->{n} = 2;
	    next;
	}
	$value = _outrange( $map, $value, $last, $min, $max );

	# Start a new interval range with this value
	$last->{start} = $next;
	$last->{end} = $next;
	$last->{interval} = 0;
	$last->{n} = 1;
    }

    # Out of values, dump final element
    if( $last->{n} < 3 ) {
	while( $last->{n} ) {
	    $value .= ',' if( length $value );
	    $value .= ucfirst $map->{'_' . $last->{start}};
	    $last ->{start} += $last->{interval};
	    $last->{n}--;
	}
    } else {
	$value = _outrange( $map, $value, $last, $min, $max );
    }

    return $value;
}

# Normally turns a string into a value
#
# In our case, we'll look for the string in the query ourself,
# and build it from pieces if possible.

sub string2value {
    my( $this, $query, $name ) = @_;

    my $xid = $name;
    $xid =~ tr /\{\}/()/;

    die "Query not available; is lib/TWiki/lib/Configure/Valuer.pm up-to-date?" unless( ref $query  eq 'CGI' );

    # If we don't have the listbox values (dow is arbitrary), we use whatever's in the full string.
    # We computed that in a previous screen.
    # If we do have the listbox values, it's a config change form, so piece the string together.

    return $query->param($name) unless( defined $query->param( $xid.'dow' ) );

    my $value = '';

    # crontab order, build record from each field

    foreach my $field (qw /min hour dom mon dow sec/) {
	$value .= ' ' unless( length $value == 0 );
	my @values = $query->param( $xid.$field );
	@values = '*' unless( @values );
	$query->delete( $xid.$field );

	# condense the value list using ranges and repeat counts

	$value .= _condense( @{ {
	                            hour => [ \%numMap, 0, 23 ],
				    dom =>  [ \%numMap, 1, 31 ],
				    dow =>  [ \%dayMap, 0, 6 ],
				    mon => [ \%monMap, 1, 12 ],
				}->{$field} || [ \%numMap, 0, 59 ]
			      }, @values );
    }
    $query->param($name,$value);

    return $value;
}

# Compare two schedules.
#  (Convenient for debugging, can omit & inherit)

sub equals {
    my ($this, $val, $def) = @_;

    return !(defined($val) xor defined($def)) if( !(defined($val) && defined($def)) );

    return $val eq $def;
}

1;
__END__

# TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2000-2006 TWiki Contributors.
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
