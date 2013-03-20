package Net::DLNA::Server::SSDP;

use 5.010;
use Moose;

use Log::Log4perl qw(get_logger :nowarn);

use IO::Socket::INET;
use IO::Socket::Multicast;

use HTTP::Headers;
use Sys::Hostname qw/hostname/;
use Digest::MD5;
use Config;

has cache_max_age => (
    is      => 'ro',
    default => '1810',
);

has http_port => (
    is      => 'ro',
    default => '8001',
);

has local_ip => (
    is      => 'ro',
    default => '192.168.1.69',
);

has local_port => (
    is      => 'ro',
    default => '1900',
);

has local_interface => (
    is      => 'ro',
    default => 'wlan0',
);

has nts => (
    is         => 'rw',
    lazy_build => 1,
);

sub _build_nts {
    my ($self)  = @_;
    return [
        $self->uuid,
        'upnp:rootdevice',
        'urn:schemas-upnp-org:device:MediaServer:1',
        'urn:schemas-upnp-org:service:ContentDirectory:1',
        'urn:schemas-upnp-org:service:ConnectionManager:1',
    ];
}

has os => (
    is => 'ro',
    default => $Config::Config{osname}
);

has os_version => (
    is => 'ro',
    default => $Config::Config{osvers}
);

has program_name => (
    is     => 'ro',
    default => 'PerlMediaServer'
);

has program_version => (
    is     => 'ro',
    default => '0.01'
);

has peer_ip => (
    is      => 'ro',
    default => '239.255.255.250',
);

has peer_port => (
    is      => 'ro',
    default => '1900',
);

has protocol => (
    is      => 'ro',
    default => 'udp',
);

has sleep_interval => (
    is      => 'rw',
    default => '3',
);

has uuid => (
    is      => 'ro',
    lazy_build => 1,
);

sub _build_uuid {
    my ($self)  = @_;
    my $md5 = Digest::MD5->new;
    $md5->add(hostname());
    my $uuid = substr($md5->digest(),0,16);
    $uuid = join '-', map { unpack 'H*', $_ } map { substr $uuid, 0, $_, '' } ( 4, 2, 2, 2, 6 );
    return 'uuid:'.$uuid;
}

#### Sockets ###

has multicast_send_socket => (
    is         => 'rw',
    lazy_build => 1,
);

sub _build_multicast_send_socket {
    my ($self)  = @_;
    my $logger = get_logger();

    $logger->debug('Creating SSDP sending socket.');
    my $socket = IO::Socket::INET->new(
        LocalAddr => $self->local_ip,
        PeerAddr  => $self->peer_ip,
        PeerPort  => $self->peer_port,
        Proto     => $self->protocol,
        Blocking  => 0,
    ) || $logger->fatal('Cannot bind to SSDP sending socket: '.$!);
    return $socket;
}

has multicast_listen_socket => (
    is         => 'rw',
    lazy_build => 1,
);

sub _build_multicast_listen_socket {
    my ($self)  = @_;
    my $logger = get_logger();

    $logger->debug('Creating SSDP Listen socket.');
    my $socket = IO::Socket::Multicast->new(
        LocalPort => $self->local_port,
        Proto     => $self->protocol,
    ) || $logger->fatal('Cannot bind to SSDP listening socket: '.$!);

    $socket->mcast_if( $self->local_interface() );
    $socket->mcast_loopback(0);
    $socket->mcast_add(
        $self->peer_ip,
        $self->local_interface,
    ) || $logger->fatal('Cannot bind to SSDP listening socket: '.$!);

    return $socket;
}

#### Module Methods ####

sub init {
    my ($self)  = @_;
    my $logger = get_logger();

    # Initialize Sockets
    $self->multicast_send_socket();
    $self->multicast_listen_socket();

    $self->_ssdp_send_byebye();
    $self->_ssdp_send_alive();
}

sub _ssdp_send_byebye {
    my $self = shift;
    my $amount = shift || 2;
    my $logger = get_logger();
    
    $logger->debug('Sending $amount SSDP byebye notify messages');
    for ( 1 .. $amount ) {
        for my $nt (@{ $self->nts }){
            $self->multicast_send_socket->send(
                "NOTIFY * HTTP/1.1\r\n"
                . "HOST: " . $self->peer_ip . ":" . $self->peer_port . "\r\n"
                . "NT: $nt\r\n"
                . "NTS: ssdp:byebye\r\n"
                . "USN: " . ( 
                    $nt eq $self->uuid? 
                    $self->uuid 
                    : $self->uuid . "::" . $nt
                ) . "\r\n"
            ) || $logger->error("Failed to send alive NT:$nt");
        }
        sleep($self->sleep_interval);
    }
}

sub _ssdp_send_alive {
    my $self = shift;
    my $amount = shift || 1;
    my $logger = get_logger();
    
    for ( 1 .. $amount ) {
        for my $nt (@{ $self->nts }){
            $self->multicast_send_socket->send(
                "NOTIFY * HTTP/1.1\r\n"
                . "HOST: " . $self->peer_ip . ":" . $self->peer_port . "\r\n"
                . "CACHE-CONTROL: max-age = " . $self->cache_max_age . "\r\n"
                . "LOCATION: http://" . $self->local_ip . ":" . $self->http_port . "/DeviceDescription.xml\r\n"
                . "NT: $nt\r\n"
                . "NTS: ssdp:alive\r\n"
                . "SERVER: " . $self->os . "/" . $self->os_version . ", UPnP/1.0, " . $self->program_name . "/" . $self->program_version . "\r\n"
                . "USN: " . ( 
                    $nt eq $self->uuid? 
                    $self->uuid 
                    : $self->uuid . "::" . $nt
                ) . "\r\n"
            ) || $logger->error("Failed to send alive NT:$nt");
        }
        sleep($self->sleep_interval);
    }
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
