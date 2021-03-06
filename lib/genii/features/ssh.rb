class Features::Ssh < Feature
  def create_dependencies
    depends_on :packages => {
                 :names => %w[openssh-client openssh-server]
               }
    depends_on :file => {
                 :name => '/etc/ssh/sshd_config',
                 :owner => :root,
                 :group => :root,
                 :mode => 0644,
                 :source => "ssh/sshd_config"
               }

    depends_on :firewall => { :tcp => 22 }

    # Install host keys for this server, if we have them
    key_dir = RelativePath.find("ssh_keys/#{configuration[:hostname]}", :ignore_missing => true)
    Dir.glob("#{key_dir}/ssh_host*").each do |path|
      filename = File.basename(path)
      depends_on :file => {
                   :name => "/etc/ssh/#{filename}",
                   :source => path,
                   :mode => /\.pub$/.match(filename) ? 0644 : 0600,
                 }
    end if key_dir

    depends_on :service => { :name => :ssh }

    unless configuration[:save_telnet]
      depends_on :packages => {
                   :name => :telnetd,
                   :uninstall => true
                 }, :do_after => self
    else
      # open the telnet port
      depends_on :firewall => { :tcp => 23 }
    end

    depends_on :monit => {
                 :name => "sshd",
                 :content => monit_content
               },
               :do_after => self

    nothing_else_to_do!
  end

  def monit_content
    """check process sshd with pidfile /var/run/sshd.pid
  start program = \"/etc/init.d/ssh start\"
  stop program = \"/etc/init.d/ssh stop\"
  if failed port 22 protocol ssh then restart
  if 3 restarts within 5 cycles then timeout
  mode manual
"""
  end
end
