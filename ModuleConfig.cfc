/**
 *********************************************************************************
 * Copyright Since 2014 CommandBox by Ortus Solutions, Corp
 * www.coldbox.org | www.ortussolutions.com | www.boxlang.io
 ********************************************************************************
 * @author Brad Wood, Luis Majano
 *
 * CommandBox Module Configuration for BoxLang Integration
 *
 * This module provides enhanced support for BoxLang servers within CommandBox.
 * It handles automatic module installation to BoxLang server homes and ensures
 * proper server configuration including Java version validation and Jakarta EE
 * compatibility through Runwar version management.
 *
 * Key Features:
 * - Intelligent BoxLang server detection and module installation
 * - Java 21+ version validation for BoxLang compatibility
 * - Automatic Jakarta EE support via Runwar 6.x for newer BoxLang versions
 * - Multiple server detection strategies (single server mode, environment variables, etc.)
 * - Backward compatibility shims for older CommandBox versions
 */
component {

	function configure(){
	}

	/**
	 * Interceptor for package installation events
	 *
	 * This method is automatically called when a package is being installed in CommandBox.
	 * For BoxLang modules (artifactDescriptor.type == "boxlang-modules"), it intelligently
	 * determines the appropriate BoxLang server home directory and redirects the installation
	 * to that location instead of the current working directory.
	 *
	 * Detection Strategy (in order of priority):
	 * 1. Check if install directory is explicitly overridden
	 * 2. Use single server mode if enabled and servers exist
	 * 3. Use server specified in interceptData.SERVERINFO.name environment variable
	 * 4. Search for BoxLang server matching current working directory
	 * 5. Check if current directory is a BoxLang server home (contains config/boxlang.json)
	 * 6. Use BOXLANG_HOME environment variable
	 * 7. Fall back to user home directory ~/.boxlang/modules/
	 *
	 * @param interceptData The interceptor data containing installation information
	 * @param interceptData.artifactDescriptor.type The type of package being installed
	 * @param interceptData.installArgs.directory Optional explicit install directory override
	 * @param interceptData.packagePathRequestingInstallation The current working directory
	 * @return void
	 *
	 * @throws void Returns early if no BoxLang server found or if server is not BoxLang type
	 */
	public void function onInstall( interceptData ){
		if ( ( interceptData.artifactDescriptor.type ?: "" ) == "boxlang-modules" ) {
			var print = wirebox.getInstance( "PrintBuffer" );

			// Exit early if install directory is explicitly overridden
			if ( !isNull( interceptData.installArgs.directory ) ) {
				local.print
					.yellowLine(
						"Install directory explicitly overriden to [#interceptData.installArgs.directory#] so not looking for a BoxLang server home to override."
					)
					.toConsole();
				return;
			}

			// Initialize required services
			var systemSettings = wirebox.getInstance( "SystemSettings" );
			var configService  = wirebox.getInstance( "ConfigService" );
			var serverService  = wirebox.getInstance( "ServerService" );
			var fileSystemUtil = wirebox.getInstance( "FileSystem" );

			var boxLangHome = "";

			// Get environment variables and server information
			var serverInfo                    = {};
			var BOXLANG_HOME                  = systemSettings.getSystemSetting( "BOXLANG_HOME", "" );
			var interceptData_serverInfo_name = systemSettings.getSystemSetting( "interceptData.SERVERINFO.name", "" );

			// Strategy 1: Check if we're in single server mode
			if ( configService.getSetting( "server.singleServerMode", false ) && serverService.getServers().count() ) {
				serverInfo  = serverService.getFirstServer();
				boxLangHome = serverInfo.serverHomeDirectory & "/WEB-INF/boxlang/modules/";
				// Strategy 2: Use server specified in environment variable
			} else if ( interceptData_serverInfo_name != "" ) {
				print.yellowLine( "Using interceptData to load server [#interceptData_serverInfo_name#]" ).toConsole();
				serverInfo = serverService.getServerInfoByName( interceptData_serverInfo_name );
				// Validate that the specified server is actually a BoxLang server
				if ( !( serverInfo.CFengine contains "boxlang" ) ) {
					local.print
						.redLine(
							"Server [#interceptData_serverInfo_name#] is of type [#serverInfo.cfengine#] and not a BoxLang server.  Ignoring."
						)
						.toConsole();
					return;
				}
				boxLangHome = serverInfo.serverHomeDirectory & "/WEB-INF/boxlang/modules/";
			} else {
				// Strategy 3: Search for BoxLang server matching current working directory
				var webroot = fileSystemUtil.resolvePath( interceptData.packagePathRequestingInstallation );
				var servers = serverService.getServers();
				for ( var serverID in servers ) {
					var thisServerInfo = servers[ serverID ];
					if (
						fileSystemUtil.resolvePath(
							path           = thisServerInfo.webroot,
							forceDirectory = true
						) == webroot
						&& thisServerInfo.CFengine contains "boxlang"
					) {
						serverInfo  = thisServerInfo;
						boxLangHome = serverInfo.serverHomeDirectory & "/WEB-INF/boxlang/modules/";
						print.yellowLine( "Found server [#serverInfo.name#] in current directory." ).toConsole();
						break;
					}
				}
				// Fallback: resolve server details for current directory
				if ( !serverInfo.count() ) {
					var serverDetails = serverService.resolveServerDetails( {} );
					serverInfo        = serverDetails.serverInfo;
					if ( !serverDetails.serverIsNew && ( serverInfo.CFengine contains "boxlang" ) ) {
						boxLangHome = serverInfo.serverHomeDirectory & "/WEB-INF/boxlang/modules/";
					} else if ( !serverDetails.serverIsNew ) {
						local.print
							.redLine(
								"Server [#serverInfo.name#] in [#interceptData.packagePathRequestingInstallation#] is of type [#serverInfo.cfengine#] and not an BoxLang server.  Ignoring."
							)
							.toConsole();
					}
				}
			}

			// Strategy 4: Check if current directory is a BoxLang server home
			var cwd = fileSystemUtil.resolvePath( interceptData.packagePathRequestingInstallation );
			if ( fileExists( cwd & "/config/boxlang.json" ) ) {
				local.print.yellowLine( "Current directory appears to be a BoxLang server home [#cwd#]" ).toConsole();
				boxLangHome = cwd & "/modules/";
			}

			// Strategy 5: Use BOXLANG_HOME environment variable
			if ( !len( boxLangHome ) && BOXLANG_HOME != "" ) {
				local.print
					.yellowLine( "Using BOXLANG_HOME environment variable to install module [#BOXLANG_HOME#]" )
					.toConsole();
				boxLangHome = BOXLANG_HOME & "/modules/";
			}

			// Strategy 6: Last resort - check user home directory
			var boxLangInUserHome = server.system.properties[ "user.home" ] & "/.boxlang/modules/"
			if ( !len( boxLangHome ) && directoryExists( boxLangInUserHome ) ) {
				local.print
					.yellowLine( "Found BoxLang home in your user's home directory [#boxLangInUserHome#]" )
					.toConsole();
				boxLangHome = boxLangInUserHome;
			}

			// Exit if no BoxLang server home could be determined
			if ( !len( boxLangHome ) ) {
				local.print
					.redLine(
						"No BoxLang server found in [#interceptData.packagePathRequestingInstallation#]. Specify the server you want by setting the name of your server into the BOXLANG_HOME environment variable."
					)
					.toConsole();
				return;
			}

			// Update interceptor data to redirect installation to BoxLang server home
			print.greenLine( "Installing into BoxLang server home [#boxLangHome#]" ).toConsole();
			interceptData.installDirectory                  = boxLangHome;
			// We'll make the boxlang home the current working directory for the install so the box.json gets managed there
			interceptData.currentWorkingDirectory           = boxLangHome.replace( "modules/", "" );
			interceptData.packagePathRequestingInstallation = interceptData.currentWorkingDirectory;
		}
		// end boxlang-modules check
	}

	/**
	 * Interceptor for server start events
	 *
	 * This method is automatically called when a server is starting in CommandBox.
	 * For BoxLang servers, it performs several critical setup tasks:
	 *
	 * 1. **Compatibility Shims**: Applies backward compatibility fixes for CommandBox versions < 6.1
	 *    - Sets empty engine name to prevent conflicts
	 *    - Configures servlet pass predicates for .cfm, .cfc, .cfcs, .bxm, and .bxs files
	 *
	 * 2. **Java Version Validation**: Ensures Java 21+ is being used (required by BoxLang)
	 *    - Executes java -version command to detect JRE version
	 *    - Throws exception if Java version is below 21
	 *
	 * 3. **Jakarta EE Support**: Automatically downloads and configures Runwar 6.x for Jakarta support
	 *    - Required for BoxLang versions newer than 1.0.0-beta26
	 *    - Downloads runwar-jakarta.jar from Ortus Solutions S3 bucket
	 *    - Overrides serverInfo.runwarJarPath to use Jakarta-compatible Runwar
	 *
	 * @param interceptData The interceptor data containing server information
	 * @param interceptData.serverInfo Server configuration object
	 * @param interceptData.serverInfo.cfengine The server engine type (must contain "boxlang")
	 * @param interceptData.serverInfo.engineVersion The BoxLang version being used
	 * @param interceptData.serverInfo.javaHome Path to Java installation
	 * @param interceptData.serverInfo.runwarOptions Server runtime options
	 * @param interceptData.serverInfo.sites Multi-site configuration (if applicable)
	 * @return void
	 *
	 * @throws commandException When Java version is below 21
	 * @throws any When Java version detection fails or Runwar download fails
	 */
	function onServerStart( interceptData ){
		var semanticVersion = wirebox.getInstance( "semanticVersion@semver" );
		var print           = wirebox.getInstance( "PrintBuffer" );
		var fileSystemUtil  = wirebox.getInstance( "FileSystem" );
		// CommandBox 6.1 has "proper" support for BoxLang servers
		var shimNeeded      = semanticVersion.isNew( shell.getversion(), "6.1.0-rc" );

		// Only process BoxLang servers
		if ( interceptData.serverInfo.cfengine contains "boxlang" ) {
			// Apply compatibility shims for older CommandBox versions
			if ( shimNeeded ) {
				print.line( "Setting engine name" ).toConsole();
				interceptData.serverInfo.runwarOptions.engineName = "";

				// Configure servlet pass predicates for CFML and BoxLang file extensions
				var newPredicate = "regex( '^/(.+?\.cf[cms])(/.*)?$' ) or regex( '^/(.+?\.bx[sm])(/.*)?$' )";
				if (
					!isNull( interceptData.serverInfo.servletPassPredicate ) && !len(
						interceptData.serverInfo.servletPassPredicate
					)
				) {
					print.line( "Setting server servletPassPredicate" ).toConsole();
					interceptData.serverInfo.servletPassPredicate = newPredicate;
				}

				// Apply servlet pass predicates to all configured sites
				if ( !isNull( interceptData.serverInfo.sites ) ) {
					for ( var siteName in interceptData.serverInfo.sites ) {
						var site = interceptData.serverInfo.sites[ siteName ];
						print.line( "Setting site [#siteName#] servletPassPredicate" ).toConsole();
						site.servletPassPredicate = newPredicate;
					}
				}
			}

			// Java version detection and validation
			try {
				var javaBin = interceptData.serverInfo.javaHome;
				// Quote java path for older CommandBox versions
				if ( shell.getversion().listGetAt( 1, "." ) < 6 ) {
					javaBin = """" & javaBin & """";
				}
				var javaVersionOutput = wirebox
					.getInstance(
						name          = "CommandDSL",
						initArguments = { name : "run" }
					)
					.params( javaBin & " -version" )
					.run( returnOutput = true );
			} catch ( any e ) {
				print.redLine( "Error checking Java version: #e.message#" ).toConsole();
				return;
			}

			// Parse Java version from output using regex
			versionSearch = javaVersionOutput.reFindNoCase(
				"""([0-9]+\.[0-9]+\.[0-9]+)""",
				1,
				true
			);
			if ( versionSearch.pos[ 1 ] && versionSearch.match.len() > 1 ) {
				var javaVersion = versionSearch.match[ 2 ]
				print.line( "Found Java version: [#javaVersion#]" ).toConsole();
				// Enforce Java 21+ requirement for BoxLang
				if ( val( javaVersion.listGetAt( 1, "." ) ) < 21 ) {
					throw(
						message = "BoxLang Requires a JRE version of 21 or higher.  Your current version is [#javaVersion#].",
						detail  = "Add [javaVersion=openjdk21] to your start command.",
						type    = "commandException"
					);
				}
			}
			javaBin = fileSystemUtil.normalizeSlashes( javaBin );
			print.line( "Verified Java 21 JRE" ).toConsole();

			// Jakarta EE support configuration
			// CommandBox 6.2 will have "proper" support for Jakarta servers
			var jakartaShimNeeded      = semanticVersion.isNew( shell.getversion(), "6.2.0" );
			var boxlangRequiresJakarta = true;
			var engineVersion          = interceptData.serverInfo.engineVersion.listFirst( "+" );

			// Determine if this BoxLang version requires Jakarta support
			// I can't use proper semver parsing because our betas aren't named beta.9 beta.10, etc. so they don't sort correctly
			if ( engineVersion contains "1.0.0-beta" ) {
				engineVersion = engineVersion.replace( "1.0.0-beta", "" );
				// betas prior to beta 26 don't require Jakarta
				if ( isNumeric( engineVersion ) && engineVersion <= 26 ) {
					boxlangRequiresJakarta = false;
				}
			}

			if ( jakartaShimNeeded ) {
				if ( boxlangRequiresJakarta ) {
					// Download and configure Runwar 6.x with Jakarta support
					var runwarJarURL         = "https://s3.amazonaws.com/downloads.ortussolutions.com/cfmlprojects/runwar/6.0.3-SNAPSHOT/runwar-6.0.3-SNAPSHOT.jar";
					var runwarJarLocal       = expandPath( "/commandbox-boxlang/lib/runwar-jakarta.jar" );
					var runwarJarFolderLocal = getDirectoryFromPath( runwarJarLocal );
					if ( !directoryExists( runwarJarFolderLocal ) ) {
						directoryCreate( runwarJarFolderLocal );
					}
					if ( !fileExists( runwarJarLocal ) ) {
						print
							.yellowLine(
								"Runwar 6.x with Jakarta support is required for BoxLang servers newer than 1.0.0-beta26. "
							)
							.toConsole();
						print.yellowLine( "Downloading from #runwarJarURL#" ).toConsole();
						try {
							http url="#runwarJarURL#" file="#runwarJarLocal#" timeout="200";
						} catch ( any e ) {
							print.redLine( "Error downloading Runwar 6.x: #e.message#" ).toConsole();
							print.redLine( "Please download it manually and place it in #runwarJarLocal#" ).toConsole();
							rthrow;
						}
					} else {
						print.line( "Runwar 6.x with Jakarta support is already installed." ).toConsole();
					}
					print.line( "Overriding serverInfo.runwarJarPath to [#runwarJarLocal#]" ).toConsole();

					// Override the default Runwar jar with Jakarta-compatible version
					interceptData.serverInfo.runwarJarPath = runwarJarLocal;
				} else {
					print
						.line(
							"BoxLang server of version [#interceptData.serverInfo.engineVersion#] does not require Jakarta support."
						)
						.toConsole();
				}
			}
		}
	}

}
