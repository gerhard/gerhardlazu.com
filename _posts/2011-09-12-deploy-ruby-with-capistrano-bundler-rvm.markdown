---
layout: post
title: Deploy a Ruby application with Capistrano, rvm & bundler
categories:
- ruby
- chef
- rvm
- bundler
- capistrano
---

## The wastelands of "sysadminia"

If you want to get your code out there, you - as a developer - need to match your
most fierce adversary: the "sysadmin". It can't be done from the comfort
of your shiny Mac development environment, you need to go out in the
wastelands of "sysadminia" where the fans howls 24/7 and sysadmins roam
with their mighty htop, tmux and pkill. There will be no clever plugins,
no IDEs, no snippets, just plain text. You will need an ally.

There are 2 weapons in particular which make all the conventional
sysadmin tools look cheap in comparison: Chef and Puppet.
You should pick one and make it your horse:
it will make a life and death difference in the wastelands. Both of
them are fine choices, go with whatever makes you most comfortable, but know this:
Chef comes with a knife. I don't use it myself, true men fight
with their bare hands, but just in case you're a stabby proc -> person,
it will suit you.

So let's assume that you've chosen Chef, your chances are already
looking good. Preparation is everything, so let's pick up some gear
first.

## Githubia

The best place for finding the most awesome gear is
[Githubia](https://github.com/search?&q=chef-cookbooks&type=Repositories).
It's a world of magic with unicorns and eternal queues.
Some say that when developers die, they all hope to end up in this land
of magic.

I will pick the [RVM](https://github.com/gchef/rvm-cookbook) & 
[bootstrap](https://github.com/gchef/bootstrap-cookbook) cookbooks.

Once you have those 2 cookbooks, this is a sample role which configures 
a server with rvm, latest Ruby 1.9.2 and sets up a new user under which
we'll deploy our Ruby app.

{% highlight ruby %}
name          "ruby_apps"
description   "Ruby Apps"
run_list      "recipe[build-essential]",
              "recipe[git]",
              "recipe[ssh]",
              "recipe[sudo]",
              "recipe[bootstrap]",
              "recipe[bootstrap::users]",
              "recipe[rvm]",
              "recipe[rvm::users]",
              "recipe[bootstrap::ruby_apps]"

default_attributes(
  :ssh => {
    :password_authentication => "no",
    :permit_root_login => "no"
  },
  :sudo => {
    :groups => ["admin"],
    :users => ["ubuntu"] # the default sudo user on Ubuntu-based EC2 AMIs
  },
  :bootstrap=> {
    :users => {
      :gerhard => {
        :admin => true,
        :deploy => true,
        :keys => [
          "my-sha-is-longer-than-your-sha",
        ]
      }
    }
  },
  :rvm_rubies => ["1.9.2"],
  :ruby_apps => ["rubyapp"]
)
{% endhighlight %}

The other cookbooks are mostly taken from the [gchef repository](https://github.com/gchef), 
everything else comes from [opscode cookbooks](https://github.com/opscode/cookbooks).

## Let's make sysadmins drool over our deploys

Once you cook your server with the above role, it will be all set up for
deploying. Before we go to the deployment files, pick some good hints
from this abridged `~/.ssh/config` file:

{% highlight bash %}
# to prevent SSH connections timing out. This will poll the server every 60".
ServerAliveInterval 60
ServerAliveCountMax 3
# use my local SSH key to authenticate on the remote hosts (when tunelling)
ForwardAgent yes

Host ec2-rubyapp
  Hostname ec2-50-19-201-63.compute-1.amazonaws.com # deploying to the cloud FTW!
  User gerhard # it will default to your username if omitted
{% endhighlight %}

Here's a `deploy.rb`, taken from a production app.

{% highlight ruby %}
# makes the output nice and colourful
# gem 'capistrano_colors'
require "capistrano_colors"

default_run_options[:pty] = true  # Must be set for the password prompt from git to work
ssh_options[:forward_agent] = true

set :application, "rubyapp"
set :repository,  "git@github.com:gerhard/#{application}.git"
set :user, application
set :use_sudo, false
set :default_shell, "/bin/bash" # required for rvm scripts to work properly

server "ec2-rubyapp", :app, :web

set :scm, :git
set :branch, "master"
set :deploy_via, :remote_cache
set :deploy_to, "/home/#{application}"
set :keep_releases, 10

set :myself, `whoami`.chomp # if more users have the same user on the server,
# with deploy privileges and ssh keys set up properly, they can deploy!
set :rvm_path, "/usr/local/rvm/scripts/rvm"

def close_sessions
  sessions.values.each { |session| session.close }
  sessions.clear
end

def with_user(new_user, &block)
  initial_user = user
  set :user, new_user
  close_sessions
  yield
  set :user, initial_user
  close_sessions
end
{% endhighlight %}

And now for the `Capfile` where all the magic happens. It assumes that
you are using [foreman](https://github.com/ddollar/foreman) for managing
your app processes. If you're not using it already, drop everything and
get it set up straight away: [David - the creator himself - introduces Foreman](http://blog.daviddollar.org/2011/05/06/introducing-foreman.html).

{% highlight ruby %}
load 'deploy' if respond_to?(:namespace) # cap2 differentiator
load 'config/deploy' # remove this line to skip loading any of the default tasks

namespace :deploy do
  task :stop, :roles => :app, :except => { :no_release => true } do
    with_user myself do
      run [
        "sudo [ -f /etc/init/#{application}.conf ]",
        "[ $(sudo status #{application} | grep -c running) -eq 1 ]",
        "sudo stop #{application} || exit 0"
      ].join(" && ")
    end
  end

  task :generate_upstart, :roles => :app, :except => { :no_release => true } do
    with_user myself do
      run [
        "source ~/.profile",
        "cd #{current_release}",
        "bundle exec foreman export upstart /tmp -u #{application} -a #{application}",
        "sudo [ -f /etc/init/#{application}.conf ] || exit 0",
        "sudo rm /etc/init/#{application}*.conf",
      ].join(" && ")
      run "sudo mv /tmp/#{application}*.conf /etc/init/"
    end
  end

  task :start, :roles => :app, :except => { :no_release => true } do
    with_user myself do
      run [
        "sudo [ -f /etc/init/#{application}.conf ]",
        "[ $(sudo status #{application} | grep -c running) -eq 0 ]",
        "sudo start #{application}"
      ].join(" && ")
    end
  end

  task :restart, :roles => :app, :except => { :no_release => true } do
    stop
    generate_upstart
    start
  end
end

task :ensure_permissions do
  run "chmod g-w #{deploy_to}"
end
after 'deploy:setup', :ensure_permissions
after 'deploy:update', :ensure_permissions

task :bundle do
  run [
    "source #{rvm_path} && cd #{release_path} &&",
    "bundle install",
    "--gemfile #{release_path}/Gemfile",
    "--path #{shared_path}/bundle",
    "--deployment --quiet",
    "--without development test"
  ].join(" ")
end
after 'deploy:finalize_update', :bundle

after 'deploy:update', 'deploy:cleanup'
{% endhighlight %}

I'm making use of upstart (running on Ubuntu, aren't you?!?), bundler &
rvm, everything just works. Chef takes care of all the burden related to
getting system-wide rvm to play nicely with user shell profiles. I'm
using bash on the server and defining it explicitly in Capistrano.
Trying to make the default Capistrano `sh` shell option work
properly with rvm is guaranteed to make your blood boil, I prefer to
play with unicorns and rainbows instead.

It might not be the most elegant solution, but it works. Everything is
nice and straightforward, tasks are pretty self explanatory and can be
tweaked to your own taste. Go on then, try some painless deploys, the feeling is
awesome!

## UPDATE

I came across Tom's gem after getting this deploy strategy in place, his
[tomafro-deploy](https://github.com/tomafro/tomafro-deploy) gem is definitely worth checking out.
