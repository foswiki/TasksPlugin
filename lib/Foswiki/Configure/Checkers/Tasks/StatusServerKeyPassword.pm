# -*- mode: CPerl; -*-
# TWiki off-line task management framework addon for the TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2011 Timothe Litt <litt at acm dot org>
# License is at end of module.
# Removal of Copyright and/or License prohibited.

use strict;
use warnings;

=pod

---+ package Foswiki::Configure::Checkers::Tasks::StatusServerKeyPassword
Configure GUI checker for the {Tasks}{StatusServerKeyPassword} configuration item.

Verifies that a password is not present unless https protocol is selected.  This is to discourage leaving a
cleartext password for something in a config file when it's not necessary.

Any problems detected are reported.

=cut

package Foswiki::Configure::Checkers::Tasks::StatusServerKeyPassword;
use base 'Foswiki::Configure::Checker';


=pod

---++ ObjectMethod check( $valueObject ) -> $errorString
Validates the {Tasks}{StatusServerKeyPassword} item for the configure GUI
   * =$valueObject= - configure value object

Returns empty string if OK, error string with any errors

=cut

sub check {
    my $this = shift;

    my $e = '';

    my $pass =  $Foswiki::cfg{Tasks}{StatusServerKeyPassword} || '';
    return $e unless( $pass );

    $Foswiki::cfg{Tasks}{StatusServerProtocol} eq 'https' or
      return $this->WARN( "Password should not be set unless https protocol is selected." );

    return $e;
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
