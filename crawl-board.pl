use v5.18;

use File::Path qw(make_path);

use Mojo::UserAgent;
use Mojo::UserAgent::CookieJar;

use constant PTT_URL => "https://www.ptt.cc";

sub ptt_get {
    my ($url) = @_;

    state $ua ||= Mojo::UserAgent->new(
        cookie_jar => Mojo::UserAgent::CookieJar->new,
    );

    my $tx = $ua->max_redirects(5)->get($url);
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
    my ($url_board_index, $board_name) = @_;

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
    # https://www.ptt.cc/bbs/Gossiping/index10355.html

    my @boards;
    $tx->res->dom->find("a[href*='/bbs/${board_name}/index']")->each(
        sub {
            return unless (my $href = $_->attr("href")) =~ m{/bbs/${board_name}/index[0-9]+\.html}x;
            push @boards, {
                url => PTT_URL . $href
            };
        }
    );
    return \@boards;
}

sub download_articles {
    my ($articles, $output_dir) = @_;
    for (@$articles) {
        my $save_as = "${output_dir}/" . $_->{id} . ".html";
        ptt_get( $_->{url} )->res->content->asset->move_to( $save_as );
        say "==> $save_as";
    }
}

sub main {
    my ($board_name, $output_dir) = @_;

    my $board_url = PTT_URL . "/bbs/${board_name}/index.html";

    my $articles = harvest_articles( $board_url, $board_name );

    my $output_board_dir = "${output_dir}/${board_name}";
    make_path($output_board_dir);
    download_articles( $articles, $output_board_dir );
}

main(@ARGV);
