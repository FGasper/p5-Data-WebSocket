#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::FailWarnings;

use Time::HiRes ();

plan tests => 1;

use Net::WebSocket::PMCE::deflate::Data::Server ();

my $data = Net::WebSocket::PMCE::deflate::Data::Server->new(
    deflate_no_context_takeover => 1,
);

my $streamer = $data->create_streamer( 'Net::WebSocket::Frame::text' );

my (@pieces, @frames);

while (@frames < 2) {
    my $piece = join( q<>, map { Time::HiRes::time() } 1 .. 5000 );

    push @pieces, $piece;

    my $method = @frames ? 'create_final' : 'create_chunk';
    my $frame = $streamer->$method($piece);

    if ($frame) {
        push @frames, $frame;
    }
}

my $msg = Net::WebSocket::Message->new(@frames);

#printf "uncompressed: %d\ncompressed: %d\n", length( join(q<>, @pieces) ), length $msg->get_payload();

is(
    $data->decompress( $msg->get_payload() ),
    join( q<>, @pieces ),
    'streamed message round-trip',
);
