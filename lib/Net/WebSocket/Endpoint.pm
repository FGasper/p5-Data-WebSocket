package Net::WebSocket::Endpoint;

use strict;
use warnings;

use Net::WebSocket::Message ();
use Net::WebSocket::X ();

use constant DEFAULT_MAX_PINGS => 2;

sub new {
    my ($class, %opts) = @_;

    my @missing = grep { !length $opts{$_} } qw( parser out );
    #die "Missing: [@missing]" if @missing;

    my $self = {
        _sent_pings => 0,
        _max_pings => DEFAULT_MAX_PINGS,
        (map { ( "_$_" => $opts{$_} ) } qw(
            parser
            out
            max_pings
        )),
    };

    return bless $self, $class;
}

#To facilitate chunking.
sub set_data_handler {
    my ($self, $todo_cr) = @_;
    $self->{'_on_data'} = $todo_cr;

    return;
}

sub get_next_message {
    my ($self) = @_;

    die "Already closed!" if $self->{'_closed'};

    if ( my $frame = $self->{'_parser'}->get_next_frame() ) {
        if ($frame->is_control_frame()) {
            $self->_handle_control_frame($frame);
        }
        else {
            if ($self->{'_on_data'}) {
                $self->{'_on_data'}->($frame);
            }

            if (!$frame->get_fin()) {
                push @{ $self->{'_fragments'} }, $frame;
            }
            else {
                return Net::WebSocket::Message::create_from_frames(
                    splice( @{ $self->{'_fragments'} } ),
                    $frame,
                );
            }
        }
    }

    return undef;
}

sub timeout {
    my ($self) = @_;

    if ($self->{'_sent_pings'} == $self->{'_max_pings'}) {
        my $close = $self->create_close('POLICY_VIOLATION');
        print { $self->{'_out'} } $close->to_bytes();
        $self->{'_closed'} = 1;
    }

    my $ping = $self->create_ping(
        payload_sr => \"$self->{'_sent_pings'} of $self->{'_max_pings'}",
    );
    print { $self->{'_out'} } $ping->to_bytes();

    $self->{'_sent_pings'}++;

    return;
}

sub is_closed {
    my ($self) = @_;
    return $self->{'_closed'} ? 1 : 0;
}

#----------------------------------------------------------------------

sub _handle_control_frame {
    my ($self, $frame) = @_;

    if ($frame->get_type() eq 'close') {
        my $rframe = $self->create_close(
            $frame->get_code_and_reason(),
        );

        local $SIG{'PIPE'} = 'IGNORE';

        print { $self->{'_out'} } $rframe->to_bytes();

        $self->{'_closed'} = 1;

        die Net::WebSocket::X->create('ReceivedClose', $frame);
    }
    elsif ($frame->get_type() eq 'ping') {
        my $pong = $self->create_pong(
            $frame->get_payload(),
        );

        print { $self->{'_out'} } $pong->to_bytes();
    }
    elsif ($frame->get_type() eq 'pong') {
        if ($self->{'_sent_pings'}) {
            $self->{'_sent_pings'}--;
        }
        else {
            my $cframe = $self->create_close(
                'PROTOCOL_ERROR',
                'pong without ping',
            );

            print { $self->{'_out'} } $cframe->to_bytes();

            $self->{'_closed'} = 1;

            die sprintf("pong (%s) without ping", $frame->get_payload());
        }
    }
    else {
        die "Unrecognized control frame ($frame)";
    }

    return;
}

1;
