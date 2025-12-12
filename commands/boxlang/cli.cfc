/**
 * Open the BoxLang CLI
 * .
 * {code:bash}
 * boxlang cli
 * {code}
 * .
 * This command has no arguments.  Any args passed positionally will be sent along to the BoxLang binary
 * .
 * {code:bash}
 * boxlang cli myFile.bxs
 * {code}
 * .
 **/
component {

	// DI
	property name="javaService"     inject="JavaService";
	property name="endpointService" inject="EndpointService";
	property name="semanticVersion" inject="provider:semanticVersion@semver";
	property name="packageService"  inject="PackageService";
	property name="commandService"  inject="CommandService";
	property name="moduleSettings"  inject="box:moduleSettings:commandbox-boxlang";

	function run(){
		var verbose        = moduleSettings.CLIVerbose ?: false;
		var javaVersion    = "openjdk21";
		var availableJavas = javaService
			.listJavaInstalls()
			.filter( ( jInstall ) => jInstall contains javaVersion )
			.map( ( name, deets ) => {
				deets.justJavaVersion = name.listLast( "-" )
				return deets;
			} )
			.valueArray()
			.sort( ( a, b ) => semanticVersion.compare( b.justJavaVersion, a.justJavaVersion ) );
		if ( availableJavas.len() ) {
			var thisJava        = availableJavas.first();
			var javaInstallPath = thisJava.directory & "/" & thisJava.name;
		} else {
			var javaInstallPath = javaService.getJavaInstallPath( javaVersion, false );
		}
		javaInstallPath &= "/bin/java";
		if ( verbose ) print.line( "Using Java from: " & javaInstallPath );

		var cmd = """#javaInstallPath#""";


		var jarInstallDir = expandPath( "/commandbox-boxlang/lib/boxlang/" );

		if ( len( moduleSettings.CLIBoxLangVersion ?: "" ) ) {
			var boxLangVersion = moduleSettings.CLIBoxLangVersion;
		} else {
			param server.checkedBoxLangLatestVersion = false;

			// TODO: setting to override version
			if ( !server.checkedBoxLangLatestVersion ) {
				var boxlangLatestVersion = getBoxLangLatestVersion()
			} else {
				var stableLocalVersions = directoryList( path = jarInstallDir )
					.map( ( d ) => d.listLast( "\/" ).replace( "boxlang-", "" ) )
					.filter( ( v ) => !semanticVersion.isPreRelease( v ) )
					.sort( ( a, b ) => semanticVersion.compare(
						b.listLast( "\/" ),
						a.listLast( "\/" )
					) )

				if ( stableLocalVersions.len() ) {
					var boxlangLatestVersion = stableLocalVersions.first();
				} else {
					var boxlangLatestVersion = getBoxLangLatestVersion()
				}
			}

			var boxLangVersion = boxlangLatestVersion;
		}
		var boxlangFileName     = "boxlang-#boxLangVersion#.jar";
		var boxlangDownloadURL  = "https://downloads.ortussolutions.com/ortussolutions/boxlang/#urlEncode( boxLangVersion )#/#urlEncode( boxlangFileName )#";
		var localBoxlangJarPath = "#jarInstallDir#/boxlang-#boxLangVersion#/#boxlangFileName#";
		if ( !fileExists( localBoxlangJarPath ) ) {
			if ( verbose ) print.line( "Downloading BoxLang jar [#boxlangVersion#]..." );
			packageService.installPackage(
				ID        = "jar:#boxlangDownloadURL#",
				directory = jarInstallDir,
				save      = false,
				verbose   = verbose
			);
		}
		cmd &= " -jar ""#localBoxlangJarPath#""";

		var i               = 0;
		var originalCommand = commandService
			.getCallStack()
			.first()
			.commandInfo
			.ORIGINALLINE
			.replace( "boxlang cli", "" );
		cmd &= " " & originalCommand;

		setBoxlangHomeToServer();
		// Prepend BOXLANG_HOME environment variable to command for Unix/Linux
		if ( !fileSystemUtil.isWindows() ) {
			cmd = "BOXLANG_HOME=""#getSystemSetting( key="BOXLANG_HOME", defaultValue="" )#"" " & cmd;
		}

		print.toConsole();
		var output = command( "run" )
			.params( cmd )
			// Try to contain the output if we're in an interactive job and there are arguments (no args opens the boxlang shell)
			.run(
				echo         = verbose,
				returnOutput = ( job.isActive() && arguments.count() )
			);

		if ( job.isActive() && arguments.count() ) {
			print.text( output );
		}
	}

	function getBoxLangLatestVersion(){
		// This is the CF engine package, but it has the same versions
		var boxlangLatestVersion = endpointService
			.getEndpoint( "forgebox" )
			.getForgeBox()
			.getEntry( "boxlang" )
			.versions
			.filter( ( v ) => !semanticVersion.isPreRelease( v.version ) )
			.sort( ( a, b ) => semanticVersion.compare( b.version, a.version ) )
			.first()
			.version;

		var semverParsedVersion            = semanticVersion.parseVersion( boxlangLatestVersion );
		// reassemble without build number
		boxlangLatestVersion               = "#semverParsedVersion.major#.#semverParsedVersion.minor#.#semverParsedVersion.revision#";
		server.checkedBoxLangLatestVersion = true;
		return boxlangLatestVersion;
	}

	private function setBoxlangHomeToServer(){
		var systemSettings = wirebox.getInstance( "SystemSettings" );
		var configService  = wirebox.getInstance( "ConfigService" );
		var serverService  = wirebox.getInstance( "ServerService" );
		var shell          = wirebox.getInstance( "Shell" );

		var boxLangHome = "";

		// Get environment variables and server information
		var serverInfo                    = {};
		var interceptData_serverInfo_name = systemSettings.getSystemSetting( "interceptData.SERVERINFO.name", "" );

		// Strategy 1: Check if we're in single server mode
		if ( configService.getSetting( "server.singleServerMode", false ) && serverService.getServers().count() ) {
			serverInfo  = serverService.getFirstServer();
			boxLangHome = serverInfo.serverHomeDirectory & "/WEB-INF/boxlang/";
			// Strategy 2: Use server specified in environment variable
		} else if ( interceptData_serverInfo_name != "" ) {
			serverInfo = serverService.getServerInfoByName( interceptData_serverInfo_name );
			// Validate that the specified server is actually a BoxLang server
			if ( !( serverInfo.CFengine contains "boxlang" ) ) {
				return;
			}
			boxLangHome = serverInfo.serverHomeDirectory & "/WEB-INF/boxlang/";
		} else {
			// Strategy 3: Search for BoxLang server matching current working directory
			var webroot = fileSystemUtil.resolvePath( shell.getPWD() );
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
					boxLangHome = serverInfo.serverHomeDirectory & "/WEB-INF/boxlang/";
					break;
				}
			}
			// Fallback: resolve server details for current directory
			if ( !serverInfo.count() ) {
				var serverDetails = serverService.resolveServerDetails( {} );
				serverInfo        = serverDetails.serverInfo;
				if ( !serverDetails.serverIsNew && ( serverInfo.CFengine contains "boxlang" ) ) {
					boxLangHome = serverInfo.serverHomeDirectory & "/WEB-INF/boxlang/";
				}
			}
		}
		if ( boxLangHome != "" ) {
			// Set BOXLANG_HOME environment variable
			systemSettings.setSystemSetting( "BOXLANG_HOME", boxLangHome );
			print.greenLine( "Set BOXLANG_HOME to [#boxLangHome#] for BoxLang CLI execution." ).toConsole();
		}
	}

}
