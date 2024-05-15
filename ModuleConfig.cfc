component {
	function configure() {

	}

	public void function onInstall( interceptData ) {
		if ( (interceptData.artifactDescriptor.type ?: "" ) == 'boxlang-modules' ) {		

			var print = wirebox.getInstance( 'PrintBuffer' );
			var systemSettings = wirebox.getInstance( 'SystemSettings' );
			var configService = wirebox.getInstance( 'ConfigService' );
			var serverService = wirebox.getInstance( 'ServerService' );
			var fileSystemUtil = wirebox.getInstance( 'FileSystem' );

			var boxLangHome = '';
			
			var serverInfo = {};
			var BOXLANG_HOME = systemSettings.getSystemSetting( 'BOXLANG_HOME', '' );
			var interceptData_serverInfo_name = systemSettings.getSystemSetting( 'interceptData.SERVERINFO.name', '' );

			if( configService.getSetting( 'server.singleServerMode', false ) && serverService.getServers().count() ){
				serverInfo = serverService.getFirstServer();
				boxLangHome = serverInfo.serverHomeDirectory & "/WEB-INF/boxlang/modules/";
			// If we're running inside of a server-related package script, use that server
			} else if( interceptData_serverInfo_name != '' ) {
				print.yellowLine( 'Using interceptData to load server [#interceptData_serverInfo_name#]' ).toConsole();
				serverInfo = serverService.getServerInfoByName( interceptData_serverInfo_name );
				if( !(serverInfo.CFengine contains 'boxlang' ) ){
					print.redLine( 'Server [#interceptData_serverInfo_name#] is of type [#serverInfo.cfengine#] and not a BoxLang server.  Ignoring.' ).toConsole();
					return;
				}
				boxLangHome = serverInfo.serverHomeDirectory & "/WEB-INF/boxlang/modules/";
			} else {
				// Look for the first BoxLang server using the current working directory as its web root
				var webroot = fileSystemUtil.resolvePath( interceptData.packagePathRequestingInstallation );
				var servers = serverService.getServers();
				for( var serverID in servers ){
					var thisServerInfo = servers[ serverID ];
					if( fileSystemUtil.resolvePath( path=thisServerInfo.webroot, forceDirectory=true ) == webroot
					&& thisServerInfo.CFengine contains 'boxlang' ){
						serverInfo = thisServerInfo;
						boxLangHome = serverInfo.serverHomeDirectory & "/WEB-INF/boxlang/modules/";
						print.yellowLine( 'Found server [#serverInfo.name#] in current directory.' ).toConsole();
						break;
					}
				}
				if( !serverInfo.count() ) {
					var serverDetails = serverService.resolveServerDetails( {} );
					serverInfo = serverDetails.serverInfo;
					if( !serverDetails.serverIsNew && (serverInfo.CFengine contains 'boxlang' ) ){
						boxLangHome = serverInfo.serverHomeDirectory & "/WEB-INF/boxlang/modules/";
					} else if( !serverDetails.serverIsNew ) {
						print.redLine( 'Server [#serverInfo.name#] in [#interceptData.packagePathRequestingInstallation#] is of type [#serverInfo.cfengine#] and not an BoxLang server.  Ignoring.' ).toConsole();
					}
				}

			// Allow an env var hint to tell us what server to use
			// BOXLANG_HOME=servername
			}
			if( !len( boxLangHome ) && BOXLANG_HOME != '' ) {
				print.yellowLine( 'Using BOXLANG_HOME environment variable to install module [#BOXLANG_HOME#]' ).toConsole();
				boxLangHome = BOXLANG_HOME;
			} 
			
			if( !len( boxLangHome ) ) {
				print.redLine( 'No BoxLang server found in [#interceptData.packagePathRequestingInstallation#]. Specify the server you want by setting the name of your server into the BOXLANG_HOME environment variable.' ).toConsole();
				return;
			}

			print.greenLine( 'Installing into BoxLang server home [#boxLangHome#]' ).toConsole();			
			interceptData.installDirectory = boxLangHome;
			
		} // end boxlang-modules check
	}

	function onServerStart( interceptData ) {
		var print = wirebox.getInstance( 'PrintBuffer' );
		var fileSystemUtil = wirebox.getInstance( 'FileSystem' );
		print.line( "onServerStart: #interceptData.serverInfo.cfengine# " ).toConsole();
		// If we're running in a BoxLang server, workaround some old behaviors
		if( interceptData.serverInfo.cfengine contains 'boxlang' ) {
			print.line( "Setting engine name " & interceptData.serverInfo.cfengine ).toConsole();
			interceptData.serverInfo.runwarOptions.engineName = '';

			
			if( !len( interceptData.serverInfo.servletPassPredicate ) ) {
				print.line( "Setting servletPassPredicate" ).toConsole();
				interceptData.serverInfo.servletPassPredicate = "regex( '^/(.+?\\.cf[cms])(/.*)?$' ) or regex( '^/(.+?\\.bx[sm])(/.*)?$' )";
			}

			try {
				var javaBin = interceptData.serverInfo.javaHome;
				var javaVersionOutput = wirebox.getInstance( name='CommandDSL', initArguments={ name : "run" } )
					.params( javaBin & " -version" )
					.run( returnOutput=true );
				} catch( any e ) {
					print.redLine( "Error checking Java version: #e.message#" ).toConsole();
				}
				// search for "x.x.x"
				versionSearch = javaVersionOutput.reFindNoCase( '"([0-9]+\.[0-9]+\.[0-9]+)"', 1, true );
				if( versionSearch.pos[1] && versionSearch.match.len() > 1 ) {
					var javaVersion = versionSearch.match[2]
					print.line( "Found Java version: [#javaVersion#]" ).toConsole();
					if( val( javaVersion.listGetAt(1,".") ) < 17 ) {
						throw( message="BoxLang Requires a JDK version of 17 or higher.  Your current version is [#javaVersion#].  Add javaVersion=openjdk17_jdk to your start command.", type="commandException" );
					}
				}
				javaBin = fileSystemUtil.normalizeSlashes( javaBin );
				javacBin = javaBin.replace( "/bin/java", "/bin/javac" );
				if( !( fileExists( javacBin ) ) ) {					
					throw( message="BoxLang Requires a JDK (not JRE). [#javacBin#] doesn't exist.  Add javaVersion=openjdk17_jdk to your start command.", type="commandException" ).toConsole();
				}
			
			print.line( "Verified Java 17 JDK" ).toConsole();

		}
		
	}


}