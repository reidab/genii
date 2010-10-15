class Features::ApacheApplication < Feature
  include SiteInfo
  # An application's configuration in Apache (see site_info for
  # more details)
  #
  # - The base URL should include http:// or https://,
  #   the domain name, and any leading path
  # - document_root is the location where the web content is based
  #   (for a Rails app, it's the path to /public)
  # - if auth_users is defined, it's a hash of users and passwords
  #   for digest authentication in this realm
  # - If it's ssl, ssl_certificate_file is required (along with an optional
  #   chain file or key file); non-SSL requests will be redirect to the SSL
  #   version unless you set non_ssl_redirect to false (or to another URL)
  # - configuration is an optional hash of extra parameters to include
  #   in the app's configuration: for example, :configuration =>
  #   { :RailsEnv => :development, :RailsBaseURI => path }
  # - or, instead of configuration, proxy (actually, reverse_proxy) to
  #   a port with :proxy_to => 8080, or a full url with
  #   :proxy_to => "http://something/"
  #
  # If all you want is default redirection for non-vhost requests,
  # just pass :redirect_to => url.
  attr_accessor *SITE_OPTIONS
  attr_accessor :redirect_to, :proxy_to, :configuration

  def initialize(options={})
    options[:url] ||= "http://localhost"
    super(options)
    self.auth_realm ||= "protected area"
  end

  def create_dependencies
    depends_on :service_restart => { :name => :apache2 }, 
               :do_after => self
  end

  def describe_options
    # Shorten any configuration we were given
    result = options.dup
    if result[:configuration].is_a? String
      result[:configuration] = result[:configuration].elided
    end
    result
  end

  def done?
    auth_done? && app_config_done?
  end

  def apply
    log(:progress, "configuring apache")

    # Write out an authfile if we're using authentication
    unless auth_done?
      File.open(auth_path, 'w') do |f|
        log(:progress){"writing #{auth_path}"}
        f.write auth_passwords
      end
    end

    # Write the app configuration
    FileUtils.mkdir_p(File.dirname(app_config_path))
    File.open(app_config_path, 'w') do |f|
      log(:progress){"writing #{app_config_path}"}
      f.write app_configuration
    end
  end

private

  def app_config_done?
    File.exist?(app_config_path)
  end

  def simple_redirection_configuration
    """  # Redirect everything
  RewriteEngine On
  RewriteRule ^.*$ #{redirect_to} [L,R]
"""
  end

  def proxy_configuration
    proxy_url = proxy_to
    proxy_url = "http://127.0.0.1:#{proxy_to}" if proxy_to.is_a?(Numeric)
    path_wildcard = uri.path == "/" ? "*" : "#{uri.path}/*"
    log(:error, "proxyconfig after: url=#{proxy_url.inspect}, to=#{proxy_to.inspect}, uri=#{uri.inspect}")
    """
    # We're a reverse proxy
    ProxyRequests Off
    ProxyVia Block
    <Proxy #{path_wildcard}>
        Order deny,allow
        Allow from all
    </Proxy>
    ProxyPass #{uri.path} #{proxy_url}
    ProxyPassReverse #{uri.path} #{proxy_url}
"""
  end

  def app_configuration
    # The details of app configuration, which'll be embedded into the
    # virtual host if this is the only app on the domain, or stuck in
    # a Directory tag in its own file if shared.
    @app_configuration ||= begin
      lines = ["# App configuration for #{name} at #{url}"]

      if document_root && shared_site? && uri.path != '/'
        lines << "  Alias #{uri.path} \"#{document_root}\""
      end

      if proxy_to
        lines << proxy_configuration
      else
        configuration_content = if redirect_to
          simple_redirection_configuration
        elsif configuration
          configuration
        end
        if configuration_content && configuration_content.strip.length > 0
          lines << if (shared_site? or document_root.nil?)
            "  <Location #{uri.path}>\n" +
              configuration_content + "\n" +
            "  </Location>"
          else
            "  DocumentRoot #{document_root}\n" +
            "  <Directory #{document_root}>\n" +
              configuration_content + "\n" +
            "  </Directory>"
          end
        end
      end

      lines << "  #{auth_config}" if auth_config
      lines.join("\n")
    end
  end
end
