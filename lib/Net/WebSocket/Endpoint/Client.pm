package Net::WebSocket::Endpoint::Client;

use strict;
use warnings;

use parent qw(
    Net::WebSocket::Endpoint
    Net::WebSocket::SerializerBase
    Net::WebSocket::Masker::Client
);

1;
