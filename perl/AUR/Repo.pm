package AUR::Repo;
use strict;
use warnings;
use v5.20;

use Carp;
use Exporter qw(import);
our @EXPORT_OK = qw(list_attr check_attr parse_db);
our $VERSION = 'unstable';

=head1 NAME

AUR::Repo - Parse contents of a local repository

=head1 SYNOPSIS

  use AUR::Repo qw(parse_db);

=head1 DESCRIPTION

=head1 AUTHORS

Alad Wenter <https://github.com/AladW/aurutils>

=cut

# Attributes which (where applicable) match AurJson, such that `aur-repo-parse --json`
# can be piped to `aur-format`.
our %repo_add_attributes = (
    'ARCH'         => ['string',  'Arch'         ],
    'BASE'         => ['string',  'PackageBase'  ],
    'DESC'         => ['string',  'Description'  ],
    'FILENAME'     => ['string',  'FileName'     ],
    'MD5SUM'       => ['string',  'Md5Sum'       ],  # too large for int32/int64
    'NAME'         => ['string',  'Name'         ],
    'PACKAGER'     => ['string',  'Packager'     ],
    'SHA256SUM'    => ['string',  'Sha256Sum'    ],  # too large for int32/int64
    'URL'          => ['string',  'URL'          ],
    'VERSION'      => ['string',  'Version'      ],
    'PGPSIG'       => ['string',  'PgpSig'       ],
    'CONFLICTS'    => ['array',   'Conflicts'    ],
    'CHECKDEPENDS' => ['array',   'CheckDepends' ],
    'DEPENDS'      => ['array',   'Depends'      ],
    'LICENSE'      => ['array',   'License'      ],
    'MAKEDEPENDS'  => ['array',   'MakeDepends'  ],
    'OPTDEPENDS'   => ['array',   'OptDepends'   ],
    'PROVIDES'     => ['array',   'Provides'     ],
    'REPLACES'     => ['array',   'Replaces'     ],
    'GROUPS'       => ['array',   'Groups'       ],
    'FILES'        => ['array',   'Files'        ],
    'BUILDDATE'    => ['numeric', 'BuildDate'    ],
    'CSIZE'        => ['numeric', 'CSize'        ],
    'ISIZE'        => ['numeric', 'ISize'        ]
);

=head2 list_attr()

List all defined attributes for a pacman database file, in sorted order.

=cut

sub list_attr {
    return sort(keys %repo_add_attributes);
}

=head2 check_attr()

=cut

sub check_attr {
    my ($attr) = @_;
    return $repo_add_attributes{$attr}->[1];
}

=head2 entry_search()

=cut

sub entry_search {
    my ($expr, $entry_data) = @_;

    if (length($expr) and defined($entry_data)) {
        # Search entry-by-entry on arrays
        if (ref($entry_data) eq 'ARRAY') {
            return grep(/$expr/, @{$entry_data});
        } else {
            return $entry_data =~ /$expr/;
        }
    } else {
        return defined($entry_data);
    }
}

=head2 parse_db()

Iterate over a pacman database file, and run a C<handler> function on each
entry. C<handler> should accept a hash representing a package in the database,
the current package count, and whether any packages follow the current one.

Parameters:

=over

=item C<$fh>

=back

=item C<$db_path>

=back

=item C<$db_name>

=back

=item C<$header>

=back

=item C<$handler>

=back

=item C<$search_expr>

=back

=item C<$search_label>

=back

=item C<@varargs>

=back

=cut

sub parse_db {
    my ($fh, $db_path, $db_name, $header, $handler, $search_expr, $search_label, @varargs) = @_;
    my $count = 0;
    my ($entry, $filename, $attr, $attr_label);

    while (my $row = <$fh>) {
        chomp($row);

        if ($row =~ /^%\Q$header\E%$/) {
            $filename = readline($fh);
            chomp($filename);

            # Evaluate condition on previous entry and run handler
            if ($count > 0) {
                if (entry_search($search_expr, $entry->{$search_label})) {
                    $handler->($entry, $count++, 0, @varargs);
                }
            } else {
                $count++;
            }
            # New entry in the database (hashref)
            %{$entry} = ();
            $entry->{'DBPath'} = $db_path;
            $entry->{'Repository'} = $db_name;
            $entry->{$repo_add_attributes{$header}->[1]} = $filename;
        }
        elsif ($row =~ /^%.+%$/) {
            if (not length($filename)) {
                die __PACKAGE__ . ": attribute '$header' not set";
            }
            $attr = substr($row, 1, -1);
            $attr_label = $repo_add_attributes{$attr}->[1];

            if (not defined $attr_label) {
                warn __PACKAGE__ . ": unknown attribute '$attr'";
                $attr_label = ucfirst(lc($attr));
            }
        }
        elsif ($row eq "") {
            next;
        }
        else {
            die unless length($attr) and length($attr_label);

            if ($repo_add_attributes{$attr}->[0] eq 'numeric') {
                $entry->{$attr_label} = $row + 0;
            }
            elsif ($repo_add_attributes{$attr}->[0] eq 'array') {
                push(@{$entry->{$attr_label}}, $row);
            }
            else {  # Unknown attributes are assumed to have string data
                $entry->{$attr_label} = $row;
            }
        }
    }
    # Process last entry
    if ($count > 0) {
        if (entry_search($search_expr, $entry->{$search_label})) {
            $handler->($entry, $count, 1, @varargs);
        } else {
            # Run handler with empty input to ensure correct termination for --json (#1120)
            $handler->(undef, $count, 1, @varargs);
        }
    }
    return $count;
}

# =head2 extract_db()

# =cut

# sub extract_db {

# }
