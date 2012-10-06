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
package Foswiki::Configure::Checkers::ErrorFileName;
use base 'Foswiki::Configure::Checker';

use strict;

use Foswiki::Configure::Checker;
use Foswiki::Configure::Load;

sub check {
    my $this = shift;

    my $logFile = $Foswiki::cfg{ErrorFileName} || "";
    $logFile =~ s/%DATE%/DATE/;
    Foswiki::Configure::Load::expandValue($logFile);
    my $e = $this->checkCanCreateFile( $logFile );
    $e = $this->ERROR($e) if $e;
    return $e;
}

1;
