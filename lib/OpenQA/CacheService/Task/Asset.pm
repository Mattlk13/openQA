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

package OpenQA::CacheService::Task::Asset;
use Mojo::Base 'Mojolicious::Plugin';

use constant LOCK_RETRY_DELAY   => 30;
use constant MINION_LOCK_EXPIRE => 99999;    # ~27 hours

use OpenQA::CacheService::Model::Cache;
use OpenQA::CacheService::Client;

sub register {
    my ($self, $app) = @_;

    $app->minion->add_task(cache_asset => \&_cache_asset);
}

sub _cache_asset {
    my ($job, $id, $type, $asset_name, $host) = @_;

    my $app = $job->app;
    my $log = $app->log;

    my $cache      = OpenQA::CacheService::Model::Cache->from_worker;
    my $client     = OpenQA::CacheService::Client->new;
    my $req        = $client->asset_request(id => $id, type => $type, asset => $asset_name, host => $host);
    my $guard_name = $client->session_token . '.' . $req->lock;

    return $job->remove unless defined $asset_name && defined $type && defined $host;
    return $job->retry({delay => LOCK_RETRY_DELAY})
      unless my $guard = $app->minion->guard($guard_name, MINION_LOCK_EXPIRE);

    my $job_prefix = "[Job #" . $job->id . "]";
    $log->debug("$job_prefix Guard: $guard_name Download: $asset_name");
    $log->debug("$job_prefix Dequeued " . $req->lock) if $client->dequeue_lock($req->lock);
    $OpenQA::Utils::app = undef;
    my $output;
    {
        open my $handle, '>', \$output;
        local *STDERR = $handle;
        local *STDOUT = $handle;
        # Do the real download
        $cache->host($host);
        $cache->get_asset({id => $id}, $type, $asset_name);
        $job->note(output => $output);
    }
    $log->debug("${job_prefix} Finished");
}

1;

=encoding utf-8

=head1 NAME

OpenQA::CacheService::Task::Asset - Cache Service task

=head1 SYNOPSIS

    plugin 'OpenQA::CacheService::Task::Asset';

=head1 DESCRIPTION

OpenQA::CacheService::Task::Asset is the task that minions of the OpenQA Cache Service
are executing to handle the asset download.

=cut
