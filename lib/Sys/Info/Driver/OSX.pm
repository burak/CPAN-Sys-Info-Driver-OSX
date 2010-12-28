package Sys::Info::Driver::OSX;
use strict;
use warnings;
use vars qw( $VERSION @ISA @EXPORT );
use base qw( Exporter   Sys::Info::Base );
use Carp qw( croak );
use Capture::Tiny qw( capture );

$VERSION = '0.73';
@EXPORT  = qw( fsysctl nsysctl sw_vers system_profiler );

use constant ERROR_NO_VALUE     => 'Can not happen! No value in output!';

use constant SYSCTL_NOT_EXISTS  =>
    qr{top    \s level \s name .+? in .+? is \s invalid}xms,
    qr{second \s level \s name .+? in .+? is \s invalid}xms,
    qr{name                    .+? in .+? is \s unknown}xms,
;

sub system_profiler {
    # SPSoftwareDataType -> os version. user
    # SPHardwareDataType -> cpu
    # SPMemoryDataType -> ramler
    my(@types) = @_;
    my($out, $error) = capture { system system_profiler => '-xml', (@types ? @types : ()) };
    require Mac::PropertyList;
    my $raw = Mac::PropertyList::parse_plist( $out )->as_perl;
    my %rv;
    foreach my $e ( @$raw ) {
        my $key = delete $e->{_dataType};
        my $value = delete $e->{_items};
        if ( @{ $value } == 1 ) {
            $value = $value->[0];
        }
        $rv{ $key } = $value;
    }
    return @types && @types == 1 ? values %rv : %rv;
}

sub sw_vers {
    my($out, $error) = capture { system 'sw_vers' };
    $_ = __PACKAGE__->trim( $_ ) for $out, $error;
    croak "Unable to capture `sw_vers`: $error" if $error;
    my %data = map { split m{:\s+?}xms, $_ } split m{\n}xms, $out;
    return %data;
}

sub fsysctl {
    my $key = shift || croak 'Key is missing';
    my $rv  = _sysctl( $key );
    my $val = $rv->{bogus} ? croak "sysctl: $key is not defined"
            : $rv->{error} ? croak "Error fetching $key: $rv->{error}"
            :                $rv->{value}
            ;
    return $val;
}

sub nsysctl {
    my $key = shift || croak 'Key is missing';
    return _sysctl($key)->{value};
}

sub _sysctl {
    my($key) = @_;
    my($out, $error) = capture { system sysctl => $key };
    my %rv;

    if ( $out ) {
        foreach my $row ( split m{\n}xms, $out ) {
            my($name, $value) = split m{:\s}xms, $row, 2;
            chomp $name;
            chomp $value;
            croak ERROR_NO_VALUE if ! $value && $value ne '0';
            $rv{ $name } = $value;
        }
    }

    my $total = keys %rv;

    $error = __PACKAGE__->trim( $error ) if $error;

    return {
        value => $total > 1 ? { %rv } : $rv{ $key },
        error => $error,
        bogus => $error ? _sysctl_not_exists( $error ) : 0,
    };
}

sub _sysctl_not_exists {
    my($error) = @_;
    return if ! $error;
    foreach my $test ( SYSCTL_NOT_EXISTS ) {
        return 1 if $error =~ $test;
    }
    return 0;
}

1;

__END__

=head1 NAME

Sys::Info::Driver::OSX - OSX driver for Sys::Info

=head1 SYNOPSIS

    use Sys::Info::Driver::OSX;

=head1 DESCRIPTION

This is the main module in the C<OSX> driver collection.

=head1 METHODS

None.

=head1 FUNCTIONS

=head2 fsysctl

f(atal)sysctl().

=head2 nsysctl

n(ormal)sysctl.

=cut
