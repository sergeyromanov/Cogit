package Git::PurePerl;
use Moose;
use MooseX::StrictConstructor;
use MooseX::Types::Path::Class;
use Compress::Zlib qw(uncompress);
use Git::PurePerl::DirectoryEntry;
use Git::PurePerl::Object;
use Git::PurePerl::Object::Blob;
use Git::PurePerl::Object::Commit;
use Git::PurePerl::Object::Tree;
use Git::PurePerl::Pack;
use Path::Class;
our $VERSION = '0.32';

has 'directory' =>
    ( is => 'ro', isa => 'Path::Class::Dir', required => 1, coerce => 1 );

has 'packs' => (
    is         => 'rw',
    isa        => 'ArrayRef[Git::PurePerl::Pack]',
    required   => 0,
    auto_deref => 1,
);

sub BUILD {
    my $self = shift;
    my $pack_dir = dir( $self->directory, '.git', 'objects', 'pack' );
    my @packs;
    foreach my $filename ( $pack_dir->children ) {
        next unless $filename =~ /\.pack$/;
        push @packs, Git::PurePerl::Pack->new( filename => $filename );
    }
    $self->packs( \@packs );
}

sub master {
    my $self = shift;
    my $master = file( $self->directory, '.git', 'refs', 'heads', 'master' );
    my $sha1;
    if ( -f $master ) {
        $sha1 = $master->slurp || confess('Missing refs/heads/master');
        chomp $sha1;
    } else {
        my $packed_refs = file( $self->directory, '.git', 'packed-refs' );
        my $content = $packed_refs->slurp
            || confess('Missing refs/heads/master');
        foreach my $line ( split "\n", $content ) {
            next if $line =~ /^#/;
            ( $sha1, my $name ) = split ' ', $line;
            last if $name eq 'refs/heads/master';
        }
    }
    return $self->get_object($sha1);
}

sub get_object {
    my ( $self, $sha1 ) = @_;
    return $self->get_object_packed($sha1) || $self->get_object_loose($sha1);
}

sub get_object_packed {
    my ( $self, $sha1 ) = @_;

    foreach my $pack ( $self->packs ) {
        my ( $kind, $size, $content ) = $pack->get_object($sha1);
        if ( $kind && $size && $content ) {
            return $self->create_object( $sha1, $kind, $size, $content );
        }
    }
}

sub get_object_loose {
    my ( $self, $sha1 ) = @_;

    my $filename = file(
        $self->directory, '.git', 'objects',
        substr( $sha1, 0, 2 ),
        substr( $sha1, 2 )
    );

    my $compressed = $filename->slurp;
    my $data       = uncompress($compressed);
    my ( $kind, $size, $content ) = $data =~ /^(\w+) (\d+)\0(.+)$/s;

    return $self->create_object( $sha1, $kind, $size, $content );
}

sub create_object {
    my ( $self, $sha1, $kind, $size, $content ) = @_;
    if ( $kind eq 'commit' ) {
        return Git::PurePerl::Object::Commit->new(
            sha1    => $sha1,
            kind    => $kind,
            size    => $size,
            content => $content,
        );
    } elsif ( $kind eq 'tree' ) {
        return Git::PurePerl::Object::Tree->new(
            sha1    => $sha1,
            kind    => $kind,
            size    => $size,
            content => $content,
        );
    } elsif ( $kind eq 'blob' ) {
        return Git::PurePerl::Object::Blob->new(
            sha1    => $sha1,
            kind    => $kind,
            size    => $size,
            content => $content,
        );
    } else {
        confess "unknown kind $kind";
    }
}

1;