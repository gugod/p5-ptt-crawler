use v5.18;

use File::Path qw(make_path);

use Mojo::IOLoop;
use Mojo::UserAgent;
use Mojo::UserAgent::CookieJar;

use constant PTT_URL => "https://www.ptt.cc";

sub ptt_get {
    my ($url, $cb) = @_;

    state $ua ||= Mojo::UserAgent->new(
        cookie_jar => Mojo::UserAgent::CookieJar->new,
        max_connections => 5,
        max_redirects   => 2,
    );

    if ($cb) {
        $ua->get(
            $url, sub {
                my ($ua, $tx) = @_;
                if (my $dom = $tx->res->dom->at("form[action='/ask/over18']")) {
                    $tx = $ua->post(
                        PTT_URL . '/ask/over18',
                        form => {
                            from => $dom->at("input[name='from']")->attr("value"),
                            yes  => "yes"
                        },
                        $cb
                    );
                } else {
                    $cb->($ua, $tx);
                }
            }
        );
        return;
    }

    my $tx = $ua->get($url);
    if (my $dom = $tx->res->dom->at("form[action='/ask/over18']")) {
        $tx = $ua->post(
            PTT_URL . '/ask/over18',
            form => {
                from => $dom->at("input[name='from']")->attr("value"),
                yes  => "yes"
            }
        );
    }
    return $tx;
}

sub harvest_articles {
    my ($url_board_index, $board_name, $cb) = @_;

    my $tx = ptt_get($url_board_index);

    my @articles;
    $tx->res->dom->find("a[href*='/bbs/${board_name}/']")->each(
        sub {
            return unless (my $href = $_->attr("href")) =~ m{ / ( M \. [0-9]+ \. A \. [A-Z0-9]{3} ) \.html$}x;
            my $subject = $_->text;
            my $article_id = $1;
            my $article_url = PTT_URL . $href;
            push @articles, {
                subject => $subject,
                url     => $article_url,
                id      => $article_id
            };
        }
    );
    return \@articles;
}

sub harvest_board_indices {
    my ($url_board_index, $board_name) = @_;
    my $tx = ptt_get($url_board_index);

    my @boards;
    $tx->res->dom->find("a[href*='/bbs/${board_name}/index']")->each(
        sub {
            return unless (my $href = $_->attr("href")) =~ m{/bbs/${board_name}/index([0-9]+)\.html}x;
            push @boards, {
                page_number => $1,
                url => PTT_URL . $href
            };
        }
    );
    @boards = @boards[1,0] if $boards[0]{page_number} > $boards[1]{page_number};
    push @boards, map {
        +{
            page_number => $_,
            url => PTT_URL . "/bbs/${board_name}/index" . $_ . ".html"
        }
    } ( $boards[0]{page_number}+1 .. $boards[1]{page_number}-1 );
    push @boards, {
        page_number => $boards[1]{page_number} + 1,
        url => $url_board_index
    };
    return \@boards;
}

sub download_articles {
    my ($articles, $output_dir) = @_;
    my $delay = Mojo::IOLoop->delay();

    my $c = 0;
    for (@$articles) {
        my $save_as = "${output_dir}/" . $_->{id} . ".html";
        next if -f $save_as;

        $c++;
        my $end = $delay->begin;
        ptt_get(
            $_->{url},
            sub {
                my ($ua, $tx) = @_;
                if ((my $res = $tx->res)->code eq '200') {
                    $res->content->asset->move_to($save_as);
                    say "[$$] ==> $save_as";
                }
                $end->();
            }
        );
        if ($c > 4) {
            $delay->wait;
            $c = 0;
        }
    }
    $delay->wait;
}

sub main {
    my ($board_name, $output_dir) = @_;

    my $board_url = PTT_URL . "/bbs/${board_name}/index.html";
    my $output_board_dir = "${output_dir}/${board_name}";
    make_path($output_board_dir);

    my $board_indices = harvest_board_indices($board_url, $board_name);
    for (sort { $b->{page_number} <=> $a->{page_number} } @$board_indices) {
        say "# $_->{url}";
        my $articles = harvest_articles($_->{url}, $board_name);
        download_articles( $articles, $output_board_dir );
    }
    Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
}

main(@ARGV);
