package Sys::Info::Driver::OSX::Device::CPU;
use strict;
use warnings;
use vars qw($VERSION);
use base qw(Sys::Info::Base);
use POSIX ();
use Carp qw( croak );
use Sys::Info::Driver::OSX;
use constant RE_SPACE => qr{\s+}xms;

$VERSION = '0.70';

sub identify {
    my $self = shift;

    if ( ! $self->{META_DATA} ) {
        my($cpu) = system_profiler( 'SPHardwareDataType' );

        my $mcpu = do {
            my $rv;
            my $mcpu = nsysctl('machdep.cpu');
            foreach my $key ( keys %{ $mcpu } ) {
                my @k = split m{[.]}xms, $key;
                my $e = $rv->{ shift @k } ||= {};
                $e = $e->{$_} ||= {} for @k;
                $e->{value} = $mcpu->{ $key };
            }
            $rv->{machdep}{cpu};
        };

        # $cpu:
        #    'boot_rom_version' => 'MBP71.0039.B0B',
        #    'machine_name' => 'MacBook Pro',
        #    'SMC_version_system' => '1.62f6',
        #    'platform_UUID' => '23985E75-7B4C-5D25-BF98-6E37D958926C',
        #    'machine_model' => 'MacBookPro7,1'

        my $mach = $self->uname->{machine} || fsysctl('hw.machine_arch');
        my $arch = $mach =~ m{ i [0-9] 86 }xmsi ? 'x86'
                 : $mach =~ m{ ia64       }xmsi ? 'IA64'
                 : $mach =~ m{ x86_64     }xmsi ? 'AMD-64'
                 :                                 $mach
                 ;

        my $name = fsysctl('hw.model');
        $name =~ s{\s+}{ }xms;
        my $byteorder = nsysctl('hw.byteorder');

        my @flags;
        foreach my $f ( @{$mcpu}{qw/ extfeatures features /} ) {
            next if ref $f ne 'HASH';
            next if ! $f->{value};
            push @flags, split RE_SPACE, __PACKAGE__->trim( $f->{value} );
        }

        $self->{META_DATA} = [];

        my%flag = map { $_ => 1 } @flags;
        # hw.cpu64bit_capable
        if ( $flag{EM64T} || grep { m{x86_64}xms } @flags ) {
            $arch = 'AMD-64';
            push @flags, 'LM';
        }

        my($cache_size) = split RE_SPACE, $cpu->{l2_cache};
        my($speed)      = split RE_SPACE, $cpu->{current_processor_speed};
        $cache_size    *= 1024;
        $speed         *= 1000;

        push @{ $self->{META_DATA} }, {
            serial_number                => $cpu->{serial_number},
            architecture                 => $arch,
            processor_id                 => 1,
            data_width                   => undef,
            address_width                => undef,
            bus_speed                    => $cpu->{bus_speed},
            speed                        => $speed,
            name                         => $cpu->{cpu_type} || $name,
            family                       => $mcpu->{family}{value},
            manufacturer                 => $mcpu->{vendor}{value},
            model                        => $mcpu->{model}{value},
            stepping                     => $mcpu->{stepping}{value},
            number_of_cores              => $mcpu->{core_count}{value},
            number_of_logical_processors => $mcpu->{cores_per_package}{value},
            L2_cache                     => { max_cache_size => $cache_size },
            flags                        => @flags ? [ sort @flags ] : undef,
            ( $byteorder ? (byteorder    => $byteorder):()),
        } for 1..$cpu->{number_processors};
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
    my $LM   = grep { $_ eq 'LM' } map { @{$_->{flags}} } $self->identify;
    return $LM ? '64' : '32';
}

1;

__END__

=head1 NAME

Sys::Info::Driver::OSX::Device::CPU - OSX CPU Device Driver

=head1 SYNOPSIS

-

=head1 DESCRIPTION

Identifies the CPU with system commands, L<POSIX>.

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
L<POSIX>.

=cut
