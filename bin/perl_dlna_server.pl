#!/usr/bin/perl

use 5.010;
use strict;
use warnings;

use lib qw/lib/;

use Log::Log4perl qw/get_logger/;

Log::Log4perl::init_and_watch('/etc/zone/Log4perl.conf', 10);
my $logger = Log::Log4perl->get_logger();

$logger->debug("Starting DLNA Server");

use Net::DLNA::Server::SSDP;

my $ssdp = Net::DLNA::Server::SSDP->new();

$ssdp->init();
