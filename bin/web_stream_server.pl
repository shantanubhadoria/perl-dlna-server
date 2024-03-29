#!/usr/bin/perl
use warnings;
use strict;

# This is the file that will be streamed.  If changed to some other
# type of file, you'll also need to fix the MIME type later on.
sub STREAM_FILE () { "/home/shantanu/tpcf.mp4" }
use Symbol qw(gensym);
use HTTP::Response;

# Include POE, POE::Component::Server::TCP, and the filters necessary
# to stream web content.
use POE qw(Component::Server::TCP Filter::HTTPD Filter::Stream);

# Spawn a web server on port 8088 of all interfaces.
POE::Component::Server::TCP->new(
  Alias        => "web_server",
  Port         => 8088,
  ClientFilter => 'POE::Filter::HTTPD',

  # Output has been flushed to the client.  If the output was
  # headers, open and begin streaming content.  Otherwise continue
  # streaming content until it has all been sent.  An error, such as
  # when the user stops a transfer, will also halt the stream.
  ClientFlushed => sub {
    my ($kernel, $heap) = @_[KERNEL, HEAP];

    # The first flush means that headers were sent.  Open the file
    # to be streamed, and switch to POE's Stream filter.  This
    # allows the content to pass through POE without being changed.
    unless ($heap->{file_to_stream}) {
      my $file_handle = $heap->{file_to_stream} = gensym();
      open($file_handle, "<" . STREAM_FILE)
        or die "could not open mp3: $!";

      # So that DOS-like systems do not perform ASCII transfers.
      binmode($file_handle);
      $heap->{client}->set_output_filter(POE::Filter::Stream->new());
    }

    # If a chunk of the streaming file can be read, send it to the
    # client.  Otherwise close the file and shut down.
    my $bytes_read = sysread($heap->{file_to_stream}, my $buffer = '', 65536);
    if ($bytes_read) {
      $heap->{client}->put($buffer);
    }
    else {
      delete $heap->{file_to_stream};
      $kernel->yield("shutdown");
    }
  },

  # A request has been received from the client.  We ignore its
  # content, but the server could be expanded to stream different
  # files based on what was asked here.
  ClientInput => sub {
    my ($kernel, $heap, $request) = @_[KERNEL, HEAP, ARG0];

    # Filter::HTTPD sometimes generates HTTP::Response objects.
    # They indicate (and contain the response for) errors.  It's
    # easiest to send the responses as they are and finish up.
    if ($request->isa("HTTP::Response")) {
      $heap->{client}->put($request);
      $kernel->yield("shutdown");
      return;
    }

    # The request is real and fully formed.  Create and send back
    # headers in preparation for streaming the music.
    my $response = HTTP::Response->new(200);
    $response->push_header('Content-type', 'video/mp4');
    $heap->{client}->put($response);

    # Note that we do not shut down here.  Once the response's
    # headers are flushed, the ClientFlushed callback will begin
    # streaming the actual content.
  }
);

# Start POE.  This will run the server until it exits.
$poe_kernel->run();
exit 0;
