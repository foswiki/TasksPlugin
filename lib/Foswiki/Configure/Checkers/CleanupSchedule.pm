# Copyright (c) 2011, Timothe Litt <litt at acm dot org>
#
# Full notice at end of file

package TWiki::Configure::Checkers::CleanupSchedule;

use warnings;
use strict;

use TWiki::Configure::Checker;

use TWiki::Configure::ScheduleChecker;
use base 'TWiki::Configure::ScheduleChecker';

sub check {
    my $this = shift;

    return $this->SUPER::check( $TWiki::cfg{CleanupSchedule} );
}

1;
__END__

#
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
