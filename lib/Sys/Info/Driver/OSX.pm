package Sys::Info::Driver::OSX;
use strict;
use warnings;
use vars qw( $VERSION @ISA @EXPORT );
use base qw( Exporter   Sys::Info::Base );
use Carp qw( croak );
use Capture::Tiny qw( capture );

$VERSION = '0.73';
@EXPORT  = qw( fsysctl nsysctl dmesg sw_vers system_profiler );

use constant ERROR_KEY_MISMATCH =>
    'Can not happen! Input name and output name mismatch: %s vs %s';

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

    if ( $out ) {
        my($key2, $val) = split m{:\s}xms, $out, 2;
        chomp $key2;
        chomp $val;
        croak sprintf ERROR_KEY_MISMATCH, $key, $key2 if $key2 ne $key;
        croak ERROR_NO_VALUE if ! $val && $val ne '0';
        $out = $val;
    }

    $error = __PACKAGE__->trim( $error ) if $error;

    return {
        value => $out,
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

sub dmesg {
    my $self = __PACKAGE__;
    my $buf  = qx(dmesg 2>&1); ## no critic (InputOutput::ProhibitBacktickOperators)
    return +() if ! $buf;

    my $skip =  1;
    my $i    = -1; ## no critic (ValuesAndExpressions::ProhibitMagicNumbers)
    my @buf;

    foreach my $line ( split m{\n}xms, $buf ) {
        chomp $line;
        $skip = 0 if $line =~ m{ \A CPU: \s }xms;
        next if $skip;
        if ( $line =~ m{ \A \s+ (.+?) \z }xms ) {
            my($key, $value) = split m{=}xms, $line, 2;
            next if ! $value;
            $buf[$i]->{_sub}{ $self->trim($key) } = $self->trim($value);
            next;
        }
        my($key, $value) = split m{:\s}xms, $line, 2;
        next if ! $value;
        next if $value eq 'filesystem full';
        $i++;
        push @buf, { $self->trim($key) => $self->trim($value) };
    }

    my %rv;
    my @pci;
    foreach my $e ( @buf ) {
        my $is_pci = grep { m{\A pci }xms } keys %{ $e };
        if ( $is_pci ) {
            push @pci, $e;
            next;
        }
        my $sub = delete $e->{_sub};
        my($key) = keys %{ $e };
        $rv{ $key } = {
            value => $e->{ $key },
            ( $sub ? %{ $sub } : () ),
        }
    }

    $rv{pci} = { map { %{ $_ } } @pci };

    if ( $rv{CPU} && ref $rv{CPU} eq 'HASH' ) {
        my %cpu = %{ $rv{CPU} };
        my @flags = $self->_extract_dmesg_flags( \%cpu, qw/ Features Features2 / );

        $cpu{value} =~ s[\s{2,}][ ]xmsg if $cpu{value};
        $cpu{flags} = [ sort @flags ] if @flags;

        if ( $cpu{Origin} && $cpu{Origin} =~ m{ \A "(.+?)" \s+ (.+?) \z }xms ) {
            $cpu{Origin} = {
                vendor => $1,
                ( map { split m{\s=\s}xms, $_ } split m/\s{2,}/xms, $2 )
            };
        }
        if ( exists $cpu{value} ) {
            $cpu{name} = delete $cpu{value};
        }

        if ( $cpu{'AMD Features'} ) {
            my @amd = $self->_extract_dmesg_flags(
                            \%cpu, 'AMD Features', 'AMD Features2'
                        );
            $cpu{AMD_flags} = [ @amd ];
        }

        $rv{CPU} = { %cpu };
    }

    return %rv;
}

sub _extract_dmesg_flags {
    my($self, $ref, @keys) = @_;
    my @raw = map { delete $ref->{ $_ } } @keys;
    my @flags;
    foreach my $flag ( @raw ) {
        next if ! $flag;
        if ( $flag =~ m{ \A (0x.+?)<(.+?)> \z }xms ) {
            push @flags, split m{,}xms, $2;
        }
    }
    return @flags;
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

=head2 dmesg

Interface to the C<dmesg> system call.

=head2 fsysctl

f(atal)sysctl().

=head2 nsysctl

n(ormal)sysctl.

=cut
