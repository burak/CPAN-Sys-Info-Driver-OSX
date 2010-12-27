package Sys::Info::Driver::OSX::Device::CPU;
use strict;
use warnings;
use vars qw($VERSION);
use base qw(Sys::Info::Base);
use Unix::Processors;
use POSIX ();
use Carp qw( croak );
use Sys::Info::Driver::OSX;

$VERSION = '0.70';

sub identify {
    my $self = shift;

    if ( ! $self->{META_DATA} ) {
        my $up   = Unix::Processors->new;
        my $mach = $self->uname->{machine} || fsysctl('hw.machine_arch'); # hw.machine?
        my $arch = $mach =~ m{ i [0-9] 86 }xmsi ? 'x86'
                 : $mach =~ m{ ia64       }xmsi ? 'IA64'
                 : $mach =~ m{ x86_64     }xmsi ? 'AMD-64'
                 :                                 $mach
                 ;
        my $name = fsysctl('hw.model');
        $name =~ s{\s+}{ }xms;
        my $byteorder = nsysctl('hw.byteorder');
        my @flags;
        push @flags, 'FPU' if nsysctl('hw.floatingpoint');

        $self->{META_DATA} = [];

        my %d = dmesg();
        if ( $d{CPU} ) {
            my %cpu = %{ $d{CPU} };
            for my $slot ( @cpu{ qw/ flags AMD_flags / } ) {
                next if ! $slot;
                push @flags, @{ $slot };
            }
        }

        push @{ $self->{META_DATA} }, {
            architecture                 => $arch,
            processor_id                 => 1,
            data_width                   => undef,
            address_width                => undef,
            bus_speed                    => undef,
            speed                        => $up->max_clock,
            name                         => $name,
            family                       => undef,
            manufacturer                 => undef,
            model                        => undef,
            stepping                     => undef,
            number_of_cores              => $up->max_physical,
            number_of_logical_processors => $up->max_online,
            L2_cache                     => {max_cache_size => undef},
            flags                        => @flags ? [ @flags ] : undef,
            ( $byteorder ? (byteorder    => $byteorder):()),
        } for 1..fsysctl('hw.ncpu');
    }
    #$VAR1 = 'Intel(R) Core(TM)2 Duo CPU     P8600  @ 2.40GHz';
    return $self->_serve_from_cache(wantarray);
}

sub load {
    my $self  = shift;
    my $level = shift;
    (my $raw = fsysctl('vm.loadavg')) =~ s<[{}]><>xmsg;
    my @loads = split m{\s}xms, __PACKAGE__->trim( $raw );
    return $loads[$level];
}

sub bitness {
    my $self = shift;
    my %i    = dmesg();
    my $cpu  = $i{CPU} || return;
    my %flags;
    foreach my $slot ( $cpu->{flags}, $cpu->{AMD_flags} ) {
        next if ! $slot;
        $flags{ $_ } = 1 for @{ $slot };
    }
    return $flags{LM} ? '64' : '32';
}

1;

__END__

=head1 NAME

Sys::Info::Driver::OSX::Device::CPU - OSX CPU Device Driver

=head1 SYNOPSIS

-

=head1 DESCRIPTION

Identifies the CPU with L<Unix::Processors>, L<POSIX>.

=head1 METHODS

=head2 identify

See identify in L<Sys::Info::Device::CPU>.

=head2 load

See load in L<Sys::Info::Device::CPU>.

=head2 bitness

See bitness in L<Sys::Info::Device::CPU>.

=head1 SEE ALSO

L<Sys::Info>,
L<Sys::Info::Device::CPU>,
L<Unix::Processors>, L<POSIX>.

=cut
