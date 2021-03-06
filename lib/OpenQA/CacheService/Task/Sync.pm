# Copyright (C) 2018 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package OpenQA::CacheService::Task::Sync;
use Mojo::Base 'Mojolicious::Plugin';

use OpenQA::CacheService::Client;
use Mojo::URL;

use constant LOCK_RETRY_DELAY   => 30;
use constant MINION_LOCK_EXPIRE => 99999;    # ~27 hours

sub register {
    my ($self, $app) = @_;

    $app->minion->add_task(cache_tests => \&_cache_tests);
}

sub _cache_tests {
    my ($job, $from, $to) = @_;

    my $app = $job->app;
    my $log = $app->log;

    my $client     = OpenQA::CacheService::Client->new;
    my $req        = $client->rsync_request(from => $from, to => $to);
    my $guard_name = $client->session_token . '.' . $req->lock;

    return $job->remove unless defined $from && defined $to;
    return $job->retry({delay => LOCK_RETRY_DELAY})
      unless my $guard = $app->minion->guard($guard_name, MINION_LOCK_EXPIRE);

    my $job_prefix = "[Job #" . $job->id . "]";
    $log->debug("$job_prefix Guard: $guard_name Sync: $from to $to");
    $log->debug("$job_prefix Dequeued ") if $client->dequeue_lock($req->lock);
    $OpenQA::Utils::app = undef;

    my @cmd = (qw(rsync -avHP), "$from/", qw(--delete), "$to/tests/");
    $log->debug("${job_prefix} Calling " . join(' ', @cmd));
    my $output = `@cmd`;
    $job->finish($? >> 8);
    $job->note(output => $output);
    $log->debug("${job_prefix} Finished");
}

1;

=encoding utf-8

=head1 NAME

OpenQA::CacheService::Task::Sync - Cache Service task Sync

=head1 SYNOPSIS

    plugin 'OpenQA::CacheService::Task::Sync';

=head1 DESCRIPTION

OpenQA::CacheService::Task::Sync is the task that minions of the OpenQA Cache Service
are executing to handle the tests and needles syncing.

=cut
