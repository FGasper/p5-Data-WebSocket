package Net::WebSocket::Handshake::Server;

=encoding utf-8

=head1 NAME

Net::WebSocket::Handshake::Server

=head1 SYNOPSIS

    my $hsk = Net::WebSocket::Handshake::Server->new(

        #required, base 64
        key => '..',

        #optional
        subprotocols => [ 'echo', 'haha' ],

        #optional, instances of Net::WebSocket::Handshake::Extension
        extensions => \@extension_objects,
    );

    #Note the need to conclude the header text manually.
    #This is by design, so you can add additional headers.
    my $resp_hdr = $hsk->create_header_text() . "\x0d\x0a";

    my $b64 = $hsk->get_accept();

=head1 DESCRIPTION

This class implements WebSocket handshake logic for a server.

Because Net::WebSocket tries to be agnostic about how you parse your HTTP
headers, this class doesn’t do a whole lot for you: it’ll give you the
C<Sec-WebSocket-Accept> header value given a base64
C<Sec-WebSocket-Key> (i.e., from the client), and it’ll give you
a “basic” response header text.

B<NOTE:> C<create_header_text()> does NOT provide the extra trailing
CRLF to conclude the HTTP headers. This allows you to add additional
headers beyond what this class gives you.

=cut

use strict;
use warnings;

use parent qw( Net::WebSocket::Handshake::Base );

use Call::Context ();
use Digest::SHA ();

use Net::WebSocket::X ();

sub new {
    my ($class, %opts) = @_;

    return bless \%opts, $class;
}

*get_accept = __PACKAGE__->can('_get_accept');

sub consume_peer_header {
    my ($self, $name => $value) = @_;

    if ($name eq 'Sec-WebSocket-Version') {
        die "wrong version" if $value ne Net::WebSocket::Constants::PROTOCOL_VERSION(); #XXX TODO
        $self->{'_version_ok'} = 1;
    }
    elsif ($name eq 'Sec-WebSocket-Key') {
        $self->{'key'} = $value;
    }
    elsif ($name eq 'Sec-WebSocket-Protocol') {
        Module::Load::load('HTTP::Headers::Util');

        for my $prot_ar ( HTTP::Headers::Util::split_header_words($value) ) {
            if (defined $prot_ar->[1]) {
                die "Invalid Sec-WebSocket-Protocol: $value";   #XXX object TODO
            }

            if (!defined $self->{'_match_protocol'}) {
                ($self->{'_match_protocol'}) = grep { $_ eq $prot_ar->[0] } @{ $self->{'subprotocols'} };
            }
        }
    }
    elsif ($name eq 'Sec-WebSocket-Extensions') {
        Module::Load::load('Net::WebSocket::Handshake::Extension');

        my @xtns = Net::WebSocket::Handshake::Extension->parse_string($value);

        for my $handler ( @{ $self->{'extensions'} } ) {
            $handler->consume_peer_extensions(@xtns);
        }
    }

    return;
}

sub valid_headers_or_die {
    my ($self) = @_;

    my @needed;
    push @needed, 'Sec-WebSocket-Version' if !$self->{'_version_ok'};
    push @needed, 'Sec-WebSocket-Key' if !$self->{'key'};

    die "Need: [@needed]" if @needed;

    return;
}

sub _create_header_lines {
    my ($self) = @_;

    Call::Context::must_be_list();

    my @prot;
    if (exists $self->{'protocol'}) {
        local $self->{'subprotocols'} = [ $self->{'protocol'} ];
        @prot = $self->_encode_subprotocols();
    }
    else {
        @prot = $self->_encode_subprotocols();  #XXX LEGACY/DEPRECATED
    }

    return (
        'HTTP/1.1 101 Switching Protocols',

        #For now let’s assume no one wants any other Upgrade:
        #or Connection: values than the ones WebSocket requires.
        'Upgrade: websocket',
        'Connection: Upgrade',

        'Sec-WebSocket-Accept: ' . $self->get_accept(),

        $self->_encode_extensions(),

        @prot,
    );
}

1;
