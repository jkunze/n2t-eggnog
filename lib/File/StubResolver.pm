package File::StubResolver;

use 5.010;
use strict;
use warnings;

our $VERSION;
$VERSION = sprintf "%s", q$Name: Release-1.00$ =~ /Release-(\d+\.\d+)/;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT = qw();
our @EXPORT_OK = qw( expand_blobs id2shadow special_elem );
our %EXPORT_TAGS = (all => [ @EXPORT_OK ]);

sub expand_blobs	{ return() };

sub id2shadow		{ return (shift) };

sub special_elem	{ return 0 };

1;

__END__


=head1 NAME

StubResolver - stub routines for advanced identifier resolution

=head1 SYNOPSIS

 use File::StubResolver;	    # import routines into a Perl script

=head1 BUGS

Probably.  Please report to jak at ucop dot edu.

=head1 COPYRIGHT AND LICENSE

Copyright 2002-2012 UC Regents.  BSD-type open source license.

=head1 SEE ALSO

L<dbopen(3)>, L<perl(1)>, L<http://www.cdlib.org/inside/diglib/ark/>

=head1 AUTHOR

John A. Kunze

=cut
