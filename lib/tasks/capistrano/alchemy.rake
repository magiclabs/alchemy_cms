namespace :alchemy do

  # TODO: split up this namespace into something that runs once on `cap install` and
  # once on every deploy
  desc "Prepare Alchemy for deployment."
  task :default_paths do
    set :alchemy_picture_cache_path,
      -> { File.join('public', Alchemy::MountPoint.get, 'pictures') }

    set :linked_dirs, fetch(:linked_dirs, []) + [
      "uploads/pictures",
      "uploads/attachments",
      fetch(:alchemy_picture_cache_path),
      "tmp/cache/assets"
    ]
    require 'pry'; binding.pry
    # TODO: Check, if this is the right approach to ensure that we don't overwrite existing settings?
    # Or does Capistrano already handle this for us?
    set :linked_files, fetch(:linked_files, []) + %w(config/database.yml)
  end

  # TODO: Do we really need this in Alchemy or should we release an official Capistrano plugin for that?
  namespace :database_yml do
    desc "Creates the database.yml file"
    task :create do
      set :db_environment, ask("the environment", fetch(:rails_env, 'production'))
      set :db_adapter, ask("database adapter (mysql or postgresql)", 'mysql')
      set :db_adapter, fetch(:db_adapter).gsub(/\Amysql\z/, 'mysql2')
      set :db_name, ask("database name", nil)
      set :db_username, ask("database username", nil)
      set :db_password, ask("database password", nil)
      default_db_host = fetch(:db_adapter) == 'mysql2' ? 'localhost' : '127.0.0.1'
      set :db_host, ask("database host", default_db_host)
      db_config = ERB.new <<-EOF
#{fetch(:db_environment)}:
  adapter: #{fetch(:db_adapter)}
  encoding: utf8
  reconnect: false
  pool: 5
  database: #{fetch(:db_name)}
  username: #{fetch(:db_username)}
  password: #{fetch(:db_password)}
  host: #{fetch(:db_host)}
EOF
      on roles :app do
        execute :mkdir, '-p', "#{shared_path}/config"
        upload! StringIO.new(db_config.result), "#{shared_path}/config/database.yml"
      end
    end
  end

  namespace :db do
    desc "Seeds the database with essential data."
    task :seed do
      on roles :db do
        within release_path do
          with rails_env: fetch(:rails_env, 'production') do
            execute :rake, 'alchemy:db:seed'
          end
        end
      end
    end

    desc "Dumps the database into 'db/dumps' on the server."
    task :dump do
      on roles :db do
        within release_path do
          timestamp = Time.now.strftime('%Y-%m-%d-%H-%M')
          execute :mkdir, '-p', 'db/dumps'
          with dump_filename: "db/dumps/#{timestamp}.sql", rails_env: fetch(:rails_env, 'production') do
            execute :rake, 'alchemy:db:dump'
          end
        end
      end
    end
  end

  namespace :import do
    desc "Imports all data (Pictures, attachments and the database) into your local development machine."
    task :all do
      on roles [:app, :db] do
        invoke('alchemy:import:pictures')
        puts "\n"
        invoke('alchemy:import:attachments')
        puts "\n"
        invoke('alchemy:import:database')
      end
    end

    desc "Imports the server database into your local development machine."
    task :database do
      on roles :db do |server|
        puts "Importing database. Please wait..."
        system db_import_cmd(server)
        puts "Done."
      end
    end

    desc "Imports attachments into your local machine using rsync."
    task :attachments do
      on roles :app do |server|
        get_files(:attachments, server)
      end
    end

    desc "Imports pictures into your local machine using rsync."
    task :pictures do
      on roles :app do |server|
        get_files(:pictures, server)
      end
    end

    def get_files(type, server)
      raise "No server given" if !server
      FileUtils.mkdir_p "./uploads"
      puts "Importing #{type}. Please wait..."
      system "rsync --progress -rue 'ssh -p #{fetch(:port, 22)}' #{server.user}@#{server.hostname}:#{shared_path}/uploads/#{type} ./uploads/"
    end

    def db_import_cmd(server)
      raise "No server given" if !server
      dump_cmd = "cd #{release_path} && bundle exec rake RAILS_ENV=#{fetch(:rails_env, 'production')} alchemy:db:dump"
      sql_stream = "ssh -p #{fetch(:port, 22)} #{server.user}@#{server.hostname} '#{dump_cmd}'"
      "#{sql_stream} | #{database_import_command(database_config['adapter'])} 1>/dev/null 2>&1"
    end
  end

  # TODO: Refactor me to use `linked_dirs`.
  # Kept for reference on what needs to be done
  #
  # namespace :shared_folders do
  #   desc "Creates the uploads and picture cache directory in the shared folder. Called after deploy:setup"
  #   task :create do
  #     on roles :app do
  #       execute :mkdir, '-p', "#{shared_path}/uploads/pictures"
  #       execute :mkdir, '-p', "#{shared_path}/uploads/attachments"
  #       execute :mkdir, '-p', fetch(:shared_picture_cache_path)
  #       execute :mkdir, '-p', "#{shared_path}/cache/assets"
  #     end
  #   end

  #   desc "Sets the symlinks for uploads and picture cache folder. Called after deploy:symlink:linked_dirs"
  #   task :symlink do
  #     on roles :app do
  #       execute :rm,    '-rf',  "#{release_path}/uploads"
  #       execute :ln,    '-nfs', "#{shared_path}/uploads #{release_path}/"
  #       execute :mkdir, '-p',   fetch(:public_path_with_mountpoint)
  #       execute :ln,    '-nfs', "#{fetch(:shared_picture_cache_path)} #{File.join(fetch(:public_path_with_mountpoint), 'pictures')}"
  #       execute :mkdir, '-p',   "#{release_path}/tmp/cache"
  #       execute :ln,    '-nfs', "#{shared_path}/cache/assets #{release_path}/tmp/cache/assets"
  #     end
  #   end
  # end

  desc "Upgrades production database to current Alchemy CMS version"
  task :upgrade do
    on roles [:app, :db] do
      within release_path do
        with rails_env: fetch(:rails_env, 'production') do
          execute :rake, 'alchemy:upgrade'
        end
      end
    end
  end

  # hook the deploy path into alchemy
  before 'import:all', 'deploy:check'
  before 'import:database', 'deploy:check'
  before 'import:pictures', 'deploy:check'
  before 'import:attachments', 'deploy:check'
  before 'upgrade', 'deploy:check'
  before 'db:seed', 'deploy:check'
  before 'db:dump', 'deploy:check'
end

namespace :load do
  task :defaults do
    invoke 'alchemy:default_paths'
  end
end

