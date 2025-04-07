/**
 *********************************************************************************
 * Copyright Since 2014 CommandBox by Ortus Solutions, Corp
 * www.coldbox.org | www.ortussolutions.com | www.boxlang.io
 ********************************************************************************
 * @author Brad Wood, Luis Majano
 */
component {

	function configure(){
	}

	public void function onInstall( interceptData ){
		if ( ( interceptData.artifactDescriptor.type ?: "" ) == "boxlang-modules" ) {
			var print          = wirebox.getInstance( "PrintBuffer" );
			var systemSettings = wirebox.getInstance( "SystemSettings" );
			var configService  = wirebox.getInstance( "ConfigService" );
			var serverService  = wirebox.getInstance( "ServerService" );
			var fileSystemUtil = wirebox.getInstance( "FileSystem" );

			var boxLangHome = "";

			var serverInfo                    = {};
			var BOXLANG_HOME                  = systemSettings.getSystemSetting( "BOXLANG_HOME", "" );
			var interceptData_serverInfo_name = systemSettings.getSystemSetting( "interceptData.SERVERINFO.name", "" );

			if ( configService.getSetting( "server.singleServerMode", false ) && serverService.getServers().count() ) {
				serverInfo  = serverService.getFirstServer();
				boxLangHome = serverInfo.serverHomeDirectory & "/WEB-INF/boxlang/modules/";
				// If we're running inside of a server-related package script, use that server
			} else if ( interceptData_serverInfo_name != "" ) {
				print.yellowLine( "Using interceptData to load server [#interceptData_serverInfo_name#]" ).toConsole();
				serverInfo = serverService.getServerInfoByName( interceptData_serverInfo_name );
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
				// Look for the first BoxLang server using the current working directory as its web root
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

			// See if the current working directory is a boxlang server home
			var cwd = fileSystemUtil.resolvePath( interceptData.packagePathRequestingInstallation );
			if ( fileExists( cwd & "/config/boxlang.json" ) ) {
				local.print.yellowLine( "Current directory appears to be a BoxLang server home [#cwd#]" ).toConsole();
				boxLangHome = cwd & "/modules/";
			}

			// Allow an env var hint to tell us what server to use
			// BOXLANG_HOME=servername
			if ( !len( boxLangHome ) && BOXLANG_HOME != "" ) {
				local.print
					.yellowLine( "Using BOXLANG_HOME environment variable to install module [#BOXLANG_HOME#]" )
					.toConsole();
				boxLangHome = BOXLANG_HOME & "/modules/";
			}

			// Last ditch attempt, look for a boxlang home in their user home directory
			var boxLangInUserHome = server.system.properties[ "user.dir" ] & "/.boxlang/modules/"
			if ( !len( boxLangHome ) && directoryExists( boxLangInUserHome ) ) {
				local.print
					.yellowLine( "Found BoxLang home in your user's home directory [#boxLangInUserHome#]" )
					.toConsole();
				boxLangHome = boxLangInUserHome;
			}

			if ( !len( boxLangHome ) ) {
				local.print
					.redLine(
						"No BoxLang server found in [#interceptData.packagePathRequestingInstallation#]. Specify the server you want by setting the name of your server into the BOXLANG_HOME environment variable."
					)
					.toConsole();
				return;
			}

			print.greenLine( "Installing into BoxLang server home [#boxLangHome#]" ).toConsole();
			interceptData.installDirectory                  = boxLangHome;
			// We'll make the boxlang home the current working directory for the install so the box.json gets managed there
			interceptData.currentWorkingDirectory           = boxLangHome.replace( "modules/", "" );
			interceptData.packagePathRequestingInstallation = interceptData.currentWorkingDirectory;
		}
		// end boxlang-modules check
	}

	function onServerStart( interceptData ){
		var semanticVersion = wirebox.getInstance( "semanticVersion@semver" );
		var print           = wirebox.getInstance( "PrintBuffer" );
		var fileSystemUtil  = wirebox.getInstance( "FileSystem" );
		// CommandBox 6.1 has "proper" support for BoxLang servers
		var shimNeeded      = semanticVersion.isNew( shell.getversion(), "6.1.0-rc" );

		// If we're running in a BoxLang server, workaround some old behaviors
		if ( interceptData.serverInfo.cfengine contains "boxlang" ) {
			if ( shimNeeded ) {
				print.line( "Setting engine name" ).toConsole();
				interceptData.serverInfo.runwarOptions.engineName = "";

				var newPredicate = "regex( '^/(.+?\.cf[cms])(/.*)?$' ) or regex( '^/(.+?\.bx[sm])(/.*)?$' )";
				if (
					!isNull( interceptData.serverInfo.servletPassPredicate ) && !len(
						interceptData.serverInfo.servletPassPredicate
					)
				) {
					print.line( "Setting server servletPassPredicate" ).toConsole();
					interceptData.serverInfo.servletPassPredicate = newPredicate;
				}

				if ( !isNull( interceptData.serverInfo.sites ) ) {
					for ( var siteName in interceptData.serverInfo.sites ) {
						var site = interceptData.serverInfo.sites[ siteName ];
						print.line( "Setting site [#siteName#] servletPassPredicate" ).toConsole();
						site.servletPassPredicate = newPredicate;
					}
				}
			}
			// Still detect Java version regardless since this is helpful
			try {
				var javaBin = interceptData.serverInfo.javaHome;
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
			// search for "x.x.x"
			versionSearch = javaVersionOutput.reFindNoCase(
				"""([0-9]+\.[0-9]+\.[0-9]+)""",
				1,
				true
			);
			if ( versionSearch.pos[ 1 ] && versionSearch.match.len() > 1 ) {
				var javaVersion = versionSearch.match[ 2 ]
				print.line( "Found Java version: [#javaVersion#]" ).toConsole();
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

			// CommandBox 6.2 will have "proper" support for Jakarta servers
			// var jakartaShimNeeded      = semanticVersion.isNew( shell.getversion(), "6.2.0" );
			var jakartaShimNeeded      = true;
			var boxlangRequiresJakarta = true;
			var engineVersion          = interceptData.serverInfo.engineVersion.listFirst( "+" );
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
					// Ensure Runwar 6.x with Jakarta support
					var runwarJarURL         = "https://s3.amazonaws.com/downloads.ortussolutions.com/cfmlprojects/runwar/6.0.0/runwar-6.0.0.jar";
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
