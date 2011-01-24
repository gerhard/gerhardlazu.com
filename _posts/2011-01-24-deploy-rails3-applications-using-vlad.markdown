---
layout: post
title: Deploy Rails 3 applications using Vlad, rvm system-wide and bundler, server via Passenger 3
categories:
- ruby
- deploy
- rvm
---

## Rails 2 + Mongrel or Passenger - the old skool approach

Deploying Rails applications was always a bit of a black art. I personally cringe when I think about how difficult it was to deploy a Rails app running on a mongrel cluster. There was only Capistrano that could pull it off, and that thing was such a pain to work with. Adding any custom tasks which needed to run at a particular time was clunky, errors which none could understand were the norm.

I experienced this whole painful process first hand back in the days, I put together a whole multi-server deployment strategy using Capistrano for a Rails 2 app. It was using Solr for searching and the various production config files were shared via an NFS mount across all servers. We have moved from Mongrel to Passenger 2 at the time, it was a massive improvement in terms of managing the whole setup. It had its kinks, but it was stable and worked well most of the time. As a matter of fact, the very same setup is still in production today, serving a few hundred requests every second.

## RVM, Bundler, Rails 3, Passenger 3

As soon as RVM and Bundler entered the stage, developing Ruby applications became much more pleasurable. Deploying was still cumbersome and you had to deal with extra steps such as loading the RVM profile correctly before setting up gems, but it was a great trade-off.

Passenger 3 with its Passenger Standalone addition is just amazing, running a self-managing set of daemons for serving Ruby applications has never been easier. It even sets up nginx 0.8.35 if it's not available and serves all static assets through it with no intervention required.

I tried resurrecting my old Capistrano approach and make it work with the new players, but it felt just as clunky as it did in the past, so it was time for a better solution.

## Vlad the Deployer

It sounds hip and non-convetional, maybe that's why I avoided it for a long time. I wish I hadn't.

So, there I had my Rails 3 application, first thing was to add a super simple *deploy.rb*:

{% highlight ruby %}
set :application, "my_rails_3_application"
set :domain, "ssh_host_defined_in_ssh_config"
set :deploy_to, "/home/deploy/my_rails_3_application"
set :repository, "git@github.com:gerhard/my_rails_3_application.git"
{% endhighlight %}

And this was my *vlad.rake* file:

{% highlight ruby %}
if Rails.env == "development"
  Vlad.load(:scm => :git, :app => nil, :web => nil)

  @goto_app_root = "cd #{release_path}"

  def run_remotely(commands)
    if commands.any?
      # we want to force a successful response if
      # no error is encountered
      # we'll also load the profile before every set of commands
      # loads RVM, which initializes environment and paths
      # sets RAILS_ENV to production
      commands.unshift("source ~/.profile") << "exit 0"
      single_command = commands.each do |cmd|
        # interpolate only if necessary
        cmd.is_a?(String) ? cmd : "#{cmd}"
      end.join(" && ")
      run single_command
    end
  end

  namespace :vlad do
    remote_task :bundle do
      # explicit path to system-wide rvm
      rvm = "/usr/local/bin/rvm"

      run_remotely([
        "#{rvm} rvmrc trust #{release_path}",
        @goto_app_root,
        "bundle install --gemfile #{release_path}/Gemfile --deployment --quiet --without development test --path #{shared_path}/bundle"
      ])
    end

    remote_task :setup_db do
      run_remotely([
        @goto_app_root,
        "rake db:drop",
        "rake db:create",
        "rake db:migrate",
        "rake import:greenpoint_to_fr"
      ])
    end

    remote_task :passenger_stop do
      passenger_stop_cmd = "bundle exec passenger stop --pid-file #{shared_path}/pids/passenger.pid"
      run_remotely([
        "if [ -e #{shared_path}/pids/passenger.pid ]; then #{@goto_app_root} && #{passenger_stop_cmd}; fi"
      ])
    end

    remote_task :passenger_start do
      passenger_start_cmd = "bundle exec passenger start --daemonize --log-file #{shared_path}/log/production.log --pid-file #{shared_path}/pids/passenger.pid"
      run_remotely([
        @goto_app_root,
        passenger_start_cmd
      ])
    end

    remote_task :passenger_restart do
      Rake::Task['vlad:passenger_stop'].invoke
      Rake::Task['vlad:passenger_start'].invoke
    end

    remote_task :ecb_refresh do
      run_remotely([
        @goto_app_root,
        "rake ecb:refresh"
      ])
    end

    task :update do
      Rake::Task['vlad:bundle'].invoke
    end

    desc "Deploys app as per deploy.rb config"
    task :deploy, :needs => :update do
      Rake::Task['vlad:migrate'].invoke
      Rake::Task['vlad:ecb_refresh'].invoke
      Rake::Task['vlad:passenger_restart'].invoke
      Rake::Task['vlad:cleanup'].invoke
    end

    desc "Deploys the app and resets the db"
    task :impale, :needs => :update do
      Rake::Task['vlad:setup_db'].invoke
      Rake::Task['vlad:ecb_refresh'].invoke
      Rake::Task['vlad:passenger_restart'].invoke
      Rake::Task['vlad:cleanup'].invoke
    end
  end
end
{% endhighlight %}
