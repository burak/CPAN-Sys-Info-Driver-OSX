package Sys::Info::Driver::OSX::Device::CPU;
use strict;
use warnings;
use vars qw($VERSION);
use base qw(Sys::Info::Base);
use POSIX ();
use Carp qw( croak );
use Sys::Info::Driver::OSX;

$VERSION = '0.70';

sub identify {
    my $self = shift;

    if ( ! $self->{META_DATA} ) {
        my($cpu) = system_profiler( 'SPHardwareDataType' );

        # $cpu:
        #    'physical_memory' => '4 GB',
        #    'serial_number' => 'W8025TMQATM',
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
        push @flags, 'FPU' if nsysctl('hw.floatingpoint');

        $self->{META_DATA} = [];

        my $optional = nsysctl('hw.optional');
        my @hwo = map   { m{\Ahw[.]optional[.](.+?)\z} }
                  grep  { $optional->{ $_ } }
                  keys %{ $optional };
        if ( @hwo ) {
            my %test = map { $_ => $_ } @hwo;
            $test{fpu} = delete $test{floatingpoint} if $test{floatingpoint};
            push @flags, keys %test;
        }

        my $b64 = grep { m{x86_64}xms } @flags;
        $arch = 'AMD-64' if $b64; # hw.cpu64bit_capable
        push @flags, 'LM' if $b64;

        my($cache_size) = split m{\s+}xms, $cpu->{l2_cache};
        my($speed) = split m{\s+}xms, $cpu->{current_processor_speed};
        $cache_size *= 1024;
        $speed      *= 1000;

        push @{ $self->{META_DATA} }, {
            architecture                 => $arch,
            processor_id                 => 1,
            data_width                   => undef,
            address_width                => undef,
            bus_speed                    => $cpu->{bus_speed},
            speed                        => $speed,
            name                         => $cpu->{cpu_type} || $name,
            family                       => undef,
            manufacturer                 => undef,
            model                        => undef,
            stepping                     => undef,
            number_of_cores              => $cpu->{number_processors},
            number_of_logical_processors => $cpu->{packages},
            L2_cache                     => { max_cache_size => $cache_size },
            flags                        => @flags ? [ @flags ] : undef,
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
