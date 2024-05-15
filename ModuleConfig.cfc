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
				boxLangHome = serverInfo.serverHomeDirectory & "/WEB-INF/boxlang/";
			// If we're running inside of a server-related package script, use that server
			} else if( interceptData_serverInfo_name != '' ) {
				print.yellowLine( 'Using interceptData to load server [#interceptData_serverInfo_name#]' ).toConsole();
				serverInfo = serverService.getServerInfoByName( interceptData_serverInfo_name );
				if( !(serverInfo.CFengine contains 'boxlang' ) ){
					print.redLine( 'Server [#interceptData_serverInfo_name#] is of type [#serverInfo.cfengine#] and not a BoxLang server.  Ignoring.' ).toConsole();
					return;
				}
				boxLangHome = serverInfo.serverHomeDirectory & "/WEB-INF/boxlang/";
			} else {
				// Look for the first BoxLang server using the current working directory as its web root
				var webroot = fileSystemUtil.resolvePath( interceptData.packagePathRequestingInstallation );
				var servers = serverService.getServers();
				for( var serverID in servers ){
					var thisServerInfo = servers[ serverID ];
					if( fileSystemUtil.resolvePath( path=thisServerInfo.webroot, forceDirectory=true ) == webroot
					&& thisServerInfo.CFengine contains 'boxlang' ){
						serverInfo = thisServerInfo;
						boxLangHome = serverInfo.serverHomeDirectory & "/WEB-INF/boxlang/";
						print.yellowLine( 'Found server [#serverInfo.name#] in current directory.' ).toConsole();
						break;
					}
				}
				if( !serverInfo.count() ) {
					var serverDetails = serverService.resolveServerDetails( {} );
					serverInfo = serverDetails.serverInfo;
					if( !serverDetails.serverIsNew && (serverInfo.CFengine contains 'boxlang' ) ){
						boxLangHome = serverInfo.serverHomeDirectory & "/WEB-INF/boxlang/";
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
			
		}
	}


}