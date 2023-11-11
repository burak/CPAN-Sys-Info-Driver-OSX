package Sys::Info::Driver::OSX::Device::CPU;

use 5.010;
use strict;
use warnings;
use parent qw(Sys::Info::Base);
use Carp qw( croak );
use POSIX ();
use Sys::Info::Driver::OSX;
use constant RE_SPACE => qr{\s+}xms;

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

        my $mach = $self->uname->{machine} || fsysctl('hw.machine_arch');
        my $arch = $mach =~ m{ i [0-9] 86 }xmsi ? 'x86'
                 : $mach =~ m{ ia64       }xmsi ? 'IA64'
                 : $mach =~ m{ x86_64     }xmsi ? 'AMD-64'
                 :                                 $mach
                 ;

        my $name = fsysctl('hw.model') || q{};
        $name =~ s{\s+}{ }xms;
        my $byteorder = nsysctl('hw.byteorder');

        my @flags;
        foreach my $f ( @{ $mcpu }{ qw/ extfeatures features / } ) {
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

        my($cps, $c2)   = @{ $cpu }{ qw/ current_processor_speed l2_cache / };
        my($cache_size) = $c2  ? split RE_SPACE, $c2  : 0;
        my($speed)      = $cps ? split RE_SPACE, $cps : 0;
        $cache_size    *= 1024 if $cache_size;
        if ( $speed ) {
            # locale might change the decimal separator
            $speed =~ s{ [,] }{.}xms;
            $speed *= 1000;
        }
        else {
            if ( $arch eq 'arm64' ) {
                if ( $< ) {
                    state $warned_non_root;
                    my $me = getpwuid $<;
                    if ( ! $warned_non_root++ ) {
                        warn "We can't probe for CPU speed for Apple Silicon with the current user $me and need root/sudo to be able to collect more information.";
                    }
                }
                else {
                    my %pm = powermetrics(
                                -s => 'cpu_power',
                                -n => 1,
                                -i => 1,
                            );
                    my %af = map { $_ => $pm{ $_ } }
                            grep { $pm{$_} ne ' 0 MHz' }
                            grep { $_ =~ m{ \QHW active frequency\E }xms }
                            keys %pm;
                    my @clusters_speed = sort { $a <=> $b}
                                            map {
                                                (
                                                    split m{\s+}xms,
                                                        __PACKAGE__->trim( $_ )
                                                )[0]
                                            }
                                            values %af;
                    # get the max. Likely P-N cluster.
                    $speed = $clusters_speed[-1];
                }
            }
        }

        my $proc_num = $cpu->{number_processors};
        $proc_num =~ s/proc (\d+).*/$1/; # M1 asymmetric cores

        push @{ $self->{META_DATA} }, {
            serial_number                => $cpu->{serial_number},
            architecture                 => $arch,
            processor_id                 => 1,
            data_width                   => undef,
            address_width                => undef,
            bus_speed                    => $cpu->{bus_speed},
            speed                        => $speed,
            name                         => $cpu->{chip_type} || $cpu->{cpu_type} || $name,
            family                       => $mcpu->{family}{value},
            manufacturer                 => $mcpu->{vendor}{value},
            model                        => $mcpu->{model}{value},
            stepping                     => $mcpu->{stepping}{value},
            number_of_cores              => $mcpu->{core_count}{value},
            number_of_logical_processors => $mcpu->{cores_per_package}{value},
            L2_cache                     => { max_cache_size => $cache_size },
            flags                        => @flags ? [ sort @flags ] : undef,
            ( $byteorder ? (byteorder    => $byteorder):()),
        } for 1..$proc_num;
    }

    return $self->_serve_from_cache(wantarray);
}

sub load {
    my $self  = shift;
    my $level = shift || 0;
    my $raw   = fsysctl('vm.loadavg') || return;
       $raw   =~ s<[{}]><>xmsg;
    my @loads = split m{\s}xms, __PACKAGE__->trim( $raw );
    if ( $level > $#loads || $level < 0 ) {
        croak "Bogus load level $level specified";
    }
    return $loads[$level];
}

sub bitness {
    my $self = shift;
    my @cpus = $self->identify or return;

    my @flags;
    foreach my $cpu ( grep { ref $_ eq 'HASH' } @cpus ) {
        if ( my $arch = $cpu->{architecture} ) {
            # Apple Silicon
            return '64' if $arch eq 'arm64';
        }
        next if ref $cpu->{flags} ne 'ARRAY';
        push @flags, @{ $cpu->{flags} };
    }

    return if ! @flags; # restricted ENV?
    my $LM = grep { $_ eq 'LM' } @flags;
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
