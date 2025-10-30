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
	property name="javaService" inject="JavaService";
	property name="endpointService" inject="EndpointService";
	property name="semanticVersion"		inject="provider:semanticVersion@semver";
	property name="packageService" inject="PackageService";
	property name="commandService" inject="CommandService";
	property name="moduleSettings" inject="box:moduleSettings:commandbox-boxlang";

	function run(){
		var verbose=moduleSettings.CLIVerbose ?: false;
		var javaVersion = "openjdk21";
		var availableJavas = javaService
			.listJavaInstalls()
			.filter( (jInstall) => jInstall contains javaVersion )
			.map( (name,deets)=>{
				deets.justJavaVersion=name.listLast( '-' )
				return deets;
			} )
			.valueArray()
			.sort( (a,b)=>semanticVersion.compare( b.justJavaVersion, a.justJavaVersion ) );
		if( availableJavas.len() ) {
			var thisJava = availableJavas.first();
			var javaInstallPath = thisJava.directory & "/" & thisJava.name;
		} else {
			var javaInstallPath = javaService.getJavaInstallPath( javaVersion, false );
		}
		javaInstallPath &= "/bin/java";
		if( verbose ) print.line( "Using Java from: " & javaInstallPath );
		
		if( fileSystemUtil.isWindows() ) {
			var cmd = '"#javaInstallPath#"';
		} else {
			var cmd = '#fileSystemUtil.getNativeShell()# "#javaInstallPath#"';
		}

		var jarInstallDir = expandPath( "/commandbox-boxlang/lib/boxlang/" );

		if( len(moduleSettings.CLIBoxLangVersion ?: '')) {
			var boxLangVersion = moduleSettings.CLIBoxLangVersion;
		} else {
			param server.checkedBoxLangLatestVersion = false;

			// TODO: setting to override version
			if( !server.checkedBoxLangLatestVersion ) {
				var boxlangLatestVersion = getBoxLangLatestVersion()
			} else {
				var stableLocalVersions = directoryList(  path=jarInstallDir )
					.map( (d)=>d.listLast( '\/' ).replace( "boxlang-", "" ) )
					.filter( (v)=>!semanticVersion.isPreRelease(v) )
					.sort( (a,b)=>semanticVersion.compare( b.listLast( '\/' ), a.listLast( '\/' ) ) )

				if( stableLocalVersions.len() ) {
					var boxlangLatestVersion = stableLocalVersions.first();
				} else {
					var boxlangLatestVersion = getBoxLangLatestVersion()
				}
			}

			var boxLangVersion = boxlangLatestVersion;
		}
		var boxlangFileName = "boxlang-#boxLangVersion#.jar";
		var boxlangDownloadURL = "https://downloads.ortussolutions.com/ortussolutions/boxlang/#URLEncode( boxLangVersion )#/#URLEncode( boxlangFileName )#";
		var localBoxlangJarPath = "#jarInstallDir#/boxlang-#boxLangVersion#/#boxlangFileName#";
		if( !fileExists( localBoxlangJarPath ) ) {
			if( verbose ) print.line( "Downloading BoxLang jar [#boxlangVersion#]..." );
			packageService.installPackage( ID="jar:#boxlangDownloadURL#", directory=jarInstallDir, save=false, verbose=verbose );
		}
		cmd &= ' -jar "#localBoxlangJarPath#"';

		var i = 0;
		var originalCommand = commandService.getCallStack().first().commandInfo.ORIGINALLINE.replace( "boxlang cli", "" );
		cmd &= " " & originalCommand;

		print.toConsole();
		var output = command( 'run' )
			.params( cmd )
			// Try to contain the output if we're in an interactive job and there are arguments (no args opens the boxlang shell)
			.run( echo=verbose, returnOutput=( job.isActive() && arguments.count() ) );

		if( job.isActive() && arguments.count() ) {
			print.text( output );
		}

	}

	function getBoxLangLatestVersion(){
		// This is the CF engine package, but it has the same versions
		var boxlangLatestVersion = endpointService
			.getEndpoint( "forgebox" )
			.getForgeBox()
			.getEntry( 'boxlang' )
			.versions
			.filter( (v)=>!semanticVersion.isPreRelease(v.version) )
			.sort( (a,b)=>semanticVersion.compare( b.version, a.version ) )
			.first()
			.version;

		var semverParsedVersion = semanticVersion.parseVersion( boxlangLatestVersion );
		// reassemble without build number
		boxlangLatestVersion = "#semverParsedVersion.major#.#semverParsedVersion.minor#.#semverParsedVersion.revision#";
		server.checkedBoxLangLatestVersion = true;
		return boxlangLatestVersion;
	}

}
