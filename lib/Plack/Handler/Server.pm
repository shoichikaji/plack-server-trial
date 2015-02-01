package Plack::Handler::Server;
use 5.008001;
use strict;
use warnings;
use Data::Dump;
use HTTP::Parser::XS 'parse_http_request';
use HTTP::Status 'status_message';
use IO::Socket::INET;
use Socket 'SOMAXCONN';
use Plack::Util;
use Parallel::Prefork;
use constant DEBUG => $ENV{DEBUG};

open my $null_io, "<", \"";
my $CRLF = "\015\012";

our $VERSION = "0.01";

sub new {
    my $class = shift;
    my %option = @_;
    $option{host} ||= '0.0.0.0';
    $option{port} ||= 5000;
    $option{max_workers} ||= 10;
    bless \%option, $class;
}

sub run {
    my ($self, $app) = @_;
    my $sock = IO::Socket::INET->new(
        Listen => SOMAXCONN,
        LocalPort => $self->{port},
        LocalAddr => $self->{host},
        Proto => 'tcp',
        ReuseAddr => 1,
    ) or die "failed to create socket: $!";

    my $pm = Parallel::Prefork->new(
        max_workers  => $self->{max_workers},
        trap_signals => {
            TERM => 'TERM',
        }
    );

    warn "Listening http://$self->{host}:$self->{port} with max_workers $self->{max_workers}...\n";

    while ($pm->signal_received ne 'TERM') {
        $pm->start and next;
        my $signal_received;
        $SIG{TERM} = sub { $signal_received++ };
        $SIG{PIPE} = "IGNORE";
        while (!$signal_received and my $conn = $sock->accept) {
            warn "child pid=$$, accept...\n";
            DEBUG and dd $conn;
            my $env = {
                SERVER_PORT => $self->{port},
                SERVER_NAME => $self->{host},
                SCRIPT_NAME => '',
                REMOTE_ADDR => $conn->peerhost,
                'psgi.version'      => [ 1, 1 ],
                'psgi.url_scheme'   => 'http',
                'psgi.input'        => $null_io,
                'psgi.errors'       => *STDERR,
                'psgi.multithread'  => Plack::Util::FALSE,
                'psgi.multiprocess' => Plack::Util::FALSE,
                'psgi.run_once'     => Plack::Util::FALSE,
                'psgi.nonblocking'  => Plack::Util::FALSE,
                'psgi.streaming'    => Plack::Util::FALSE,
            };
            $conn->sysread( my $buffer, 4096 );

            my $reqlen = parse_http_request $buffer, $env;
            DEBUG and dd $env;

            my $res = Plack::Util::run_app $app, $env;

            my @lines = ("HTTP/1.1 $res->[0] @{[ status_message $res->[0] ]}$CRLF");
            my @headers = @{ $res->[1] };
            for (my $i = 0; $i < $#headers; $i += 2) {
                next if $headers[$i] eq 'Connection';
                push @lines, "$headers[$i]: $headers[$i + 1]$CRLF";
            }
            push @lines, "Connection: close$CRLF$CRLF";
            $conn->syswrite( join "", @lines );
            for my $chunk (@{$res->[2]}) {
                $conn->syswrite($chunk);
            }
            $conn->close;
        }
        if ($signal_received) {
            warn "child pid=$$, catch signal, exit\n";
        }
        $pm->finish;
    }
    $pm->wait_all_children;
    warn "graceful shutdown?\n";
}

1;
__END__

=encoding utf-8

=head1 NAME

Plack::Handler::Server - personal trial

=head1 SYNOPSIS

    $ plackup -s Server -e 'sub {[200,[],["ok"]]}'

=head1 DESCRIPTION

Copy from http://www.slideshare.net/kazeburo/yapc2013psgi-plack page 53.

=head1 AUTHOR

Shoichi Kaji E<lt>skaji@cpan.orgE<gt>

=cut
