function [fmecadb,data0out,dataout,options] = fmecaengine2(varargin)
%FMECAENGINE: advanced script/function (object-oriented) to launch complex FMECA calculations from an OpenOffice Spreadsheet
%
%   USAGE AS A SCRIPT (depreciated)
%   Once the section "path and file definitions" properly defined, you need only to press F5 (i.e. run)
%   To override default values, define user variables in the workspace
%   
%   USAGE AS A FUNCTION (recommended)
%     Syntax: fmecaengine('variable1','value1','variable2','value2','variable3','value3',...)
%             fmecaengine(definition,...) whith definition a structure with fields definition.variable1 = 'value1'
%       
%   LIST OF USER VARIABLES
%               local  root directory of all files and folders (default = pwd)
%           inputpath  folder that contains all inputs (relative to local, default = 'inputs')
%          outputpath  folder that contains all outputs (relative to local, default = 'outputs')
%       fmecamainfile  filename of ODSfile (located in inputpath, default = 'fmeca_demo.ods')
%                      a structure (matching the output data0) can be used instead to link several calls of fmecaengine (use inputpath to
%                      setup the pattern for output filenames, it must include an )
%         fmecadbfile  fmecadbfile of the meta database (default = 'fmecabaseofconditions.mat')
%      fmecasheetname  name of spreadheet that (default = 'sim')
%                      If you use several sheets, do not use same id between sheets as it will be break the consistency of simulations
%            database  a database to feed all numeric input values (with statistics if needed) including Foscale, Kscale
%                      a structure such database.table.column than can be indexed as valueA:table::columnA->columnB
%                      a valid ODS file that code for a similar structure (table=sheetname, column names=first row)
%                      By default, FMECAENGINE assumes that fmecamainfile is a such database
%        enginesingle engine for single step simulation (default = @(S) senspatankar(senspatankar_wrapper(S)))
%       enginerestart engine for multiple simulations (default = @(S)senspatankarC(senspatankar_wrapper(S))) 
%        enginedelete engine to manage deleted/added layers on the fly (default = @(S)senspatankarC(senspatankar_wrapper(S)))
%        enginesetoff engine to manage setoff and periodic boundary conditions (default = setoffpatankar(senspatankar_wrapper(S)))
%            severity vectorized anonymous function to define severity (default = @(CF,SML) 100*99./max(100*SML./CF-1,0))
%                     Alternative, define first NOELfact = 100;
%                     @(CF,SML) NOELfact*(NOELfact-1)./max(NOELfact*SML./CF-1,0)
%              sample anonymous function to setup how a one->many or a many->many relationship is sampled
%                      default = @(x) prctile(x,[5 50 95]) (only 5th, 50th and 95th percentiles are considered
%                      versions older than 0.43 used @(x) [min(x) median(x) max(x)]
%                      Note that Foscale and Kscale derived from one->many or a many->many relationships are normalized from the median of
%                      the sample: setdiff(sample,median(sample))/median(sample)
%   ADDITIONAL PROPERTIES FOR ADVANCED USERS (change solver performances used in senspatankar and variants, enable linked instances of fmecaengine)
%             nograph flag value (default=true) to prevent graphs from being plotted
%              noplot flag value (default=false) to prevent any plot
%              nohtml flag value (default=false) to prevent html generation
%             options ODESET structure
%                     default value = odeset('RelTol',1e-4,'AbsTol',1e-4,'Initialstep',1e-8,'Maxstep',1e3,'Maxorder',2); % note based on dimensionless times
%               nmesh number of finite volumes for a layer with a dimensionless thickness of 1 (accurate for most of purposes)
%                     default value = 200
%            nmeshmin minimum number of mesh for a layer
%                     default value = 10;
%       fmecamainfile  matching the output structure data0 can be used instead of a filename to link several calls of fmecaengine
%           inputpath (when fmecamainfile is a structure) setups the pattern for output filenames (it must include the extension .ods)
%
%   OTHER PROPERTIES (to change the behavior of fmecaengine, mainly for developers, see code for additional details)
%             headers number of header lines (default=2) in fmecamainfile:fmecasheetname
%     databaseheaders number of header lines (default=1) in database file
%           regular_l, regular_D, regular_K, regular_C:
%                 regular expressions to identify column titles matching l,D,K,C
%           print_id, print_parent, print_inherit, print_l, print_D, print_K, print_C, print_t, print_L, print_Bi:
%                 expressions (matching fprintf syntax) to name layers id,parent,inherit,l,D,K,C,t,L,Bi           
%
%   OUTPUTS
%   fmecadb = fmecaenfine(...) returns the global database listing all conditions
%   [fmecadb,data0,data,options] = fmecaenfine(...) returns the input parameters as a structure
%       data0: initial content of fmecamainfile as a structure
%        data: state of data0 after execution of fmecaengine
%     options: options used in the current instance of fmecaengine
%
%   OUTPUT FILES (located in outputpath)
%       raw MAT files for post-processing
%       HTML report with linked PNG and PDF files (individual simulations, dependence/inheritance/result graphs, Pareto charts)
%
% DETAILED DESCRIPTION
% > The current script reads the spreadsheet 'sim' from an ODS file (OpenOffice Spreadsheet) to setup complex migration simulations.
% > Possible simulations (possibly combined) include: multilayer, chained scenarios, setoff effect, hot-filling, sterilization...
% > Titles in the spreadsheet are used to recognize variables/inputs.
% > Please, check closely the structure of the demonstration ODS file (fmeca_demo.ods) before using this script.
% > Each row in the spreadsheet codes for a single simulation. The spreadsheet can contains an arbitrary number of rows.
%
% > A column "id" is used to identify each simulation inputs and outputs.
% > Complex chaining of simulations is enabled by using the column "parent" that gives the id of the previous result
%   to be used as input for the next simulation.
%   The script does not post-process the simulations. It stores all intermediate simulations results as a MAT file (id.mat).
%   For routine control, a corresponding id.png and id.pdf, including the concentration profile and concentration cinetic
%   with twice the requested time, are also saved together.
%   A metadatabase 'fmecadb' (data about simulations), whose filename is defined by the variable fmecadbfile, stores all
%   simulation conditions including solver parameters.
%
% > The script manages the prioritization and history of all simulations regardless their order in the spreadsheet and
%   their chaining complexity (only limitation: a single parent).
%   
% > For dependent simulations, default input inheritence is also accepted so that only modified parameters need to be specified
%   and all other variables/inputs can be left empty.
% > The script detects any change in unputs and restart all dependent simulations in cascade.
% > Removing any id.MAT file or the entire output directory forces corresponding simulations to be restarted.
% > Removing an entry id in 'fmecadb' (with the command rmfield) is the same as removing the corresponding id.MAT
%   (the corresponding MAT file will be rewritten).
%
% > Inheritance of the sole inputs (while discarding simulations results) is possible via an optional column 'inherit'.
%   All empty or NaN cells are replaced by their equivalent contents from the row with id corresponding to 'inherit'.
%   Complex propagation are allowed for inheritance (e.g. cascading, tree) whatever the dependence enforced by parent.
%   In case of conflicts between inputs inheritance between 'parent' and 'inherit', the later have a higher precedence.
%   As a rule of thumb, use 'parent' to chain simulations and prefer 'inherit' for sensitivity analysis
%   (e.g. to calculate Jacobians).
%
% > Combinatory simulations (Full or pseudo Monte-Carlo [preferred]) are setup via special columns that contain vectors of scaling values.
%   A valid Matlab syntax embedded with a string can be used to define vectors (1:3, [.1 10], logspace(-3,3,10) ...)
%   Note that the scaling value 1 is removed from the list as the original row with defined values is considered to be
%   the reference simulation with a unitary scaling (i.e. no scaling).
%   Tree bifurcations/ramifications induced by multiple values are automatically generated. New id are based on original 
%   id by combining the name of scaling variable (e.g. Fo or K) the following tree level (1..m) and the scaling value (1..n).
%   Row vectors (e.g. 1:3) do not propagate scaling values to children (to simulate different contact times at a step).
%   Column vectors (e.g. (1:3)') propagate scaling values to children (to simulate different classes of molecules).
%   Currently, the following scaling parameters are recognized:
%       Foscale scale to simulate indifferently variable diffusion time and diffusion coefficients
%       Kscale to simulate different chemical affinity.
%
% > To assess the effect of a single setup, use 0 as scaling parameter (non-propagable value). The corresponding step
%   will be removed. When required, new roots are added to the simulation tree.
%
%   FMECAENGINE can be linked with internal and external databases with the keyword 'database' and relational syntaxes (see KEY2KEY).
%   EXAMPLES for fmeca_demo3.ods:
%    100*(test_key:sim::id->CP20) to reuse the concentration value of the simulation with the id test_key
%    1000*min(PP:polymer::name->classadditives:substance::class->SML) replacing a numerical SML value
%    min(Dpiringer(PP,PP:polymer::name->classadditives:substance::class->M,40)) replacing a numerical D value
%    Dpiringer(PP,max(PP:polymer::name->classadditives:substance::class->M),40) replacing a numerical D value
%    Dpiringer(PP,PP:polymer::name->classadditives:substance::class->M,40) replacing a numerical D value and setting up Foscale values
%  ADVANCED SYNTAXES (see key2key examples for further details)
%   e.g. request based on alternatives
%       HDPE|PP:polymer::name->classadditives:substance::class->M
%   e.g. request based on superclass defined in "polymerfamily": polyolefin = 'LLDPE;LDPE;MDPE;HDPE;PP'
%   polyolefin:polymerfamily::name->polymer:polymer::name->classadditives:substance::class->name:substance::name->M
%   e.g. request based on regular expressions (simple regular expressions are accepted)
%   \antiUV{3|2}\ :substance::name->M
%
% > FMECAENGINE is designed to run in paralell (trough several instances) on the computing cluster of JRU 1145
%   on either Windows or Linux (preferred for efficiency) nodes.
% > Please write, an additional script or function for complex post-treatment. It was not the intend of this function. Please,
%   note that for accuracy while preserving memory a linear time scale is used for kinetics and a time scale propertional to the
%   square root of time is used for concentration profiles.
%
% ADDITIONAL COMMENTS
%   Note 1: To add more layers, update the spreadsheet consistently (no need to modify this script/function)
%   Note 2: It is expected that simulation chaining is applied to consistent structures (i.e. with a same number of layers)
%   Note 3: Any negative Bi value is interpreted as "setoff" simulation (to be placed as a starting node)
%   Note 4: Any change in solver paremeters is also detected and forces the whole database to be recaculated
%           (use different output folders to store the results from different strategies if required)
%   Note 5: For debugging purposes, the structure array s stores all simulation parameters in same order as in the original
%           spreadsheet. Use r = senspatankar(senspatankar_wrapper(s(i))) to restart the ith simulation
%   Note 6: Creation of PDF files on the fly may interact with antivirus software on windows systems. If you get randomly
%           messages such as "print at XXX %temp%\tempfile.ps: Cannot open file: permission denied.", restart the script/function
%           and it should solve the issue.
%   Note 7: If you restart FMECAengine with a modified topology (e.g. the user removed one or several steps), impacted steps
%           will be correctly updated but the deleted steps will not be removed from the database of results. As undesirable steps
%           might impart future interpreations, it is recommended either to restart the whole project or to remove by hands with
%           rmfield the unnecessary steps in the object fmecadb (stored in fmecadbfile). It is worth to notice that FMECAengine
%           regenerate all its plots by reading each time 'sim' so that deleted steps are correctly detected and removed from
%           graphical plots.
%   Note 8: Additional columns/properties (e.g. SML) supplied in 'sim' must be considered as informative tought they may be stored
%           in fmecadb. Changing their values will not force FMECAengine to restart simulations or to update its databases.
%   Note 9: FMECAengine decides to restart simulations ONLY when its detects that the results of a simulation can be modified
%           according to the input parameters supplied to SENSPATANKAR, SENSPATANKARC, SETOFFPATANKAR... Dependent steps
%           are forced to update to keep the consistency of results.
%  Note 10: FMECAengine can be called without any ODS file and can generate for you the equivalent of a 'sim' spreadsheet
%           General syntax is: fmecaengine('fmecamainfile',{'nlayers',nlayers,'nsteps',nsteps,'keyword','property1',value1,'property2',value2,...})
%           where nlayers is the number of layers and nsteps the number of steps (they will be called 'STEP01','STEP02',etc.)
%           list od available keywords is 'make' or 'constructor')
%               > make = fmecaengine('fmecamainfile',{...,'make',...}) is set to be used as fmecaengine(make) and contains all parameters
%               > template = fmecaengine('fmecamainfile',{...,'constructor',...}) generates a 'sim' template to be used as
%                                                                                 fmecaengine('fmecamainfile',template,..)
%               > without keywords, the simulation continues (note that templates contain only NaN values)
%           property/value are used to assign spectic value in the template (note that values can be also assigned using template(istep).property=value
%           example: a = fmecaengine('fmecamainfile',{'nlayers',3,'nsteps',2,'constructor','l1m',1e-3})
%           example with shorthands: a = fmecaengine('fmecamainfile',{'nlayers',2,'nsteps',2,'constructor','l',{[1e-3 1e-4] [1e-3 1e-4]}})
%           List of shorthands:    l: 'l%dm'; D: 'D%dm2s'; KFP: 'KFP%dkgm3kgm3'; CP: 'CP%d0kgm3'
%  Note 11: all intermediate results are also exported as CSV files for external use (English delimiter apply, see print_csv to change these settings)
%           they are located at the place as corresponding PDF and PNG files
%  Note 12: To remove a layer after step 1 (example: the overpackaging is removed), set a negative concentration
%           
%
% =============================================================================
% DOCUMENTATION for open systems and complex flows (starting from version 0.6)
% =============================================================================
%   a persistent RAMDISK is used where all results are stored within a single session
%        KEYWORD: 'ramdisk' (to be combined with 'noprint' 'nograph' for maximum efficiency)
%                 'savememory' accelerate calculations and reduce memory usage (please unload fmecaengine2 with clear functions)
%       PROPERTY: 'session' sets session name (default = autoprojectname(5,true))
%       RAMDISK sessions can be managed via KEYWORDS 'ls' 'flush' 'delete' (they can be combined, 'delete' is executed the last)
%           'ls': list sessions (set session='' or session='all' to list all)
%        'flush': flush sessions on disk (set session={'session1','sessions2',...} or session='all')
%       'delete': delete sessions set in 'session' from memory
%   NEW FIELDS TO MANAGE FLOWS
%            CF0: initial concentration in F (units control to be implemented later)
%         static: flag, if true inputs of the considered step are converted into results without running any simulation
%                 it enables to set the concentration in reservoirs
%        parentF: parent step which defines CF(t=0) insteads of parent (conventional case)
%          flowF: weight fraction to account for variable flow rates (scalar value)
%
% Basic example: drip system (perfusion) decomposed as 5 segments and 100 time steps
% NB: this example does not consider explicitely the length of the tube
%{
      % Build the simulation project (simple tubbing): 490 simulations (execution time about 90 s, memory used 1450 MB)
      S0 = struct('nlayers',1,'nsteps',1,'idusercode',{'step1'},'l',6e-4,'D',1e-11,'KFP', 1,'CP',525,'CF0',0,'ts',1000,'lFm',6.7e-4,'Binounit',50);
      project = 'armed'; template = fmecaengine2('fmecamainfile',{'constructor','session',project,S0,'parent','','parentF',''});
      nz = 5; nt = 100; S = repmat(template,nz*nt - nz*(nz-1)/2,1); stepname = @(it,iz) sprintf('t%04dz%04d',it,iz); istep=0; 
      for it = 1:nt, for iz = 1:nz, if it>=iz, istep = istep + 1;
         S(istep) = template; S(istep).idusercode = stepname(it,iz);
         if it>iz, S(istep).parent = stepname(it-1,iz); else S(istep).parent = ''; end    % no parent before the first step
         if iz>1, S(istep).parentF = stepname(it-1,iz-1); else S(istep).parentF = ''; end % no parentF for the first
      end, end, end
      % Run simulation
      t0 = clock; R = fmecaengine2('fmecamainfile',S(:),'ramdisk','nograph',true,'noprint',true,'nohtml',true,'noplot');
      fmecaengine2('session',project,'ls','ramdisk'), dispf('\n>> Total execution time: %0.4g s',etime(clock,t0))
      % Extract concentration profiles
      profile = repmat(struct('t',[],'CF',[]),nz,1); for iz = 1:nz; profile(iz).t  = iz:nt; profile(iz).CF = arrayfun(@(it) R.(stepname(it,iz)).CF,iz:nt); end
      figure, plotpub({profile.t},{profile.CF}), xlabel('time')  
%}
% TODO LIST: a surrogate tube4fmecaengine() is underdevelopement
% =============================================================================
%
%
% SEE ALSO: FMECASINGLE FMECAROOT BUILDMARKOV KEY2KEY LOADFMECAENGINEDB FMECAGRAPH, FMECAMERGE
% SEE ALSO: FMECAunit, FMECAvp, FMECADpiringer, FMECADfuller, FMECAkair, FMECAgpolymer, FMECAKairP, FMECAdensity
%
% DEPENDENCY INFORMATION TO IMPLEMENT THIS SCRIPT/FUNCTION IN OTHER PROJECTS
% > Dependencies to other functions (written by INRA\Olivier Vitrac)
% See also: ARGCHECK(*), BUILDMARKOV(*), CELLCMP(*), DISPB, DISPF, DPIRINGER(*), FILEINFO, FIND_MULTIPLE(*), FORMATFIG, FORMATAX,
%           KEY2KEY(*), LOCALNAME, LOADODS(*), LOADFMECENGINEDB (*), MATCHINGCLOSINGSYMBOL, MATCMP(*), NEARESTPOINT(*), PRINT_PDF, PRINT_PNG, RGB, SENSPATANKAR(*),
%           SENSPATANKARC(*), SETOFFPATANKAR(*), STRUCTCMP(*), SUBPLOTS, SUBSTRUCTARRAY(*), WRAPTEXT
% (*) indispensable functions (shared between toolboxes Migration and MS)
% > Commercial tooboxes required: Bioinformatics Toolbox (only for Graph plotting)
% 
% DEMO (Fmecaengine v0.25)
%         fmecaengine(... without auto expansion
%             'local','C:\Data\Olivier\INRA\Etudiants & visiteurs\Audrey Goujon\illustration_fmeca\',...
%             'fmecamainfile','illustration_fmecaengine.ods',...
%             'inputpath','inputs', ...
%             'outputpath','tmp' ...
%             );
%         fmecaengine(... automatic expansion
%             'local','C:\Data\Olivier\INRA\Etudiants & visiteurs\Audrey Goujon\illustration_fmeca\',...
%             'fmecamainfile','illustration2_fmecaengine.ods',...
%             'inputpath','inputs', ...
%             'outputpath','tmp2' ...
%             );
%
% DEMO (Fmecaengine v0.27)
%         fmecaengine(...
%             'local','C:\Data\Olivier\INRA\Etudiants & visiteurs\Audrey Goujon\illustration_fmeca\',...
%             'fmecamainfile','illustration3_fmecaengine.ods',...
%             'inputpath','inputs', ...
%             'outputpath','tmp3' ...
%             );
% 
%         fmecaengine(...
%             'local','C:\Data\Olivier\INRA\Etudiants & visiteurs\Audrey Goujon\illustration_fmeca\',...
%             'fmecamainfile','illustration4_fmecaengine.ods',...
%             'inputpath','inputs', ...
%             'outputpath','tmp4' ...
%             );
%
% UNDOCUMENTED EXAMPLES
%   see simulation_template.m
%
%
% Maintenance command (before any major update)
%   cd 'C:\Data\Olivier\INRA\Codes\migration\opensource\FMECAengine'; find . -type f -iname '*.m' -o  -iname '*.asv' -o -iname '*.m~' | zip -rTgp -9 "${PWD##*/}_backup_`hostname`_`date +"%Y_%m_%d__%H-%M"`.zip" -@
%
% CONTACT
% Any question to this script/function must be addressed to: olivier.vitrac@agroparistech.fr
% The script/function was designed to run on the cluster of JRU 1145 Food Process Engineering (admin: Olivier Vitrac)
%
% Migration 2.1 (Fmecaengine v0.61) - 10/04/2011 - INRA\Olivier Vitrac - Audrey Goujon - Mai Nguyen - rev. 30/08/2017

% Revision history
% 06/04/2011 release candidate
% 09/04/2011 simulation chaining, setoff, strict input control
% 10/04/2011 propagate updates due to dependence (via parent)
% 19/04/2011 add inherit field (to propagate inheritance of the sole inputs)
%            fix existing MAT file but missing entry in fmecadb
%            additional help and comments within the code
% 21/04/2011 translated into a function, fix inherit errors
% 22/04/2011 add advanced and other properties, fix help issues
% 24/04/2011 add HTML output with CSS (source: http://icant.co.uk/csstablegallery/tables/99.php)
%            add print_id, print_parent, print_inherit
% 25/04/2011 additional CSS (source: http://www.code-sucks.com/css%20layouts/fixed-width-css-layouts/)
%            full information details in generated HTML table
% 27/04/2011 add multiple scaling and nested scaling, nested functions
% 28/04/2011 major fixes for multiple scaling, graph plot
% 29/04/2011 fix CF when senspatankarC is used, sqrt scale for interpolating solution at time t
% 30/04/2011 implement 0 to remove a nodes, protect parenting from to be inherited, add trucated PNG for graphs
%            add inheritance graph (with a different color scheme), add links
% 01/05/2011 add charts for concentration results, add nograph
% 02/05/2011 accept data0 as fmecaengine (inputpath for output pattern), interpret CF results vs path length
% 03/05/2011 fix regular expressions for checking whether PNG and PDF files exist, several bug fixes when data0 is used as input
% 04/05/2011 add kinetics (version 0.32)
% 08/05/2011 add key coding to link fmecaengine to internal or external databases (version 0.34), wrap text
% 09/05/2011 fix nfo, add severity=@(CF,SML) 100*99./max(100*SML./CF-1,0) (version 0.35)
%            add new Pareto chart for severity, keys are now accepted for Kscale and Foscale
% 10/05/2011 unified use of key2key (key2key load by itself the database if required and interpret all strings including Foscale and Kscale)
%            add noprint (version 0.36)
% 11/05/2011 fix copy of subtrees (modified PropagetScale(), findgrandchildren()), add ApplyInheritanceStrategy (version 0.37 major update)
% 12/05/2011 fix parenting after removing several nodes (version 0.38)
% 13/05/2011 fix naming between several calls of fmecaengine, plot CF and severity for upstream and downstream prunning (version 0.39)
% 16/05/2011 fix graphs without any parent (only orphans), fix union with NaN values in Foscale, Kscale
% 17/05/2011 add inherit to fmecadb, cumulate nfo content in original nodes (not duplicated) (version 0.40)
% 18/05/2011 fix missing inherit in data when stored in fmecadb (version 0.41)
% 17/07/2011 updated help, key2key based on ismemberlist instead of ismember, list/alternative are now accepted in databases (version 0.42)
% 18/07/2011 updated help, implementation of basic regular expressions in key2key
% 24/08/2011 add sample
% 25/08/2011 use nearestpoint in keyval = keysample(nearestpoint(median(keysample),keysample)); keysample = setdiff(keysample,keyval); 
% 26/08/2011 update help
% 30/08/2011 'database',struct([]) and diplay a warning when values in base are used as inputs
% 30/08/2011 replace denormal numbers in CF plots (absolute value lower than realmin) by 0 (http://en.wikipedia.org/wiki/Denormal_number)
%            see the following bug (no plot): figure, ha=plot([1 2],[0 0.035]*9.9e-323)
% 31/08/2011 add Notes 7-9, fix user override of default values with variables in base when they are not of type char
% 24/10/2011 minor fixes, add CF and CP%d to result table (version 0.49)
% 24/10/2011 fix no color when CF=0 for all steps (no contamination). It occurs when FMECAengine is used along with Bi=0 (no mass transfer in F) (version 0.491)
% 26/10/2011 fix two </tr>\n, </th>\n badly printed since 0.491 (version 0.492)
% 26/10/2011 add nmeshmin (version 0.493)
% 28/10/2011 fix unmodified inputs when CP\d was stored in output table, fix warning message (version 0.494)
% 29/10/2011 consolidated ApplyInheritanceStrategy(), inheritance applied before propagating Foscale and Kscale (version 0.495)
% 08/10/2011 fix iconpath when the toolbox migration is not installed (machines outside our laboratory) (version 0.496)
% 08/10/2011 fix iconpath when fmecaengine is in the path (version 0.497)
% 28/11/2011 check whether the toolbox BIOINFO is installed (if not graphs are disabled), implementation of GRAPHVIZ is pending (version 0.498)
% 01/12/2011 fix default sample value when prctile (from the Statistics Toolbox) is not available (version 0.499)
% 03/12/2011 fix error message, add today (version 0.4991) - this version has been tested on a Virtual Machine running R2011b without any toolbox
% 19/12/2011 in graphs, replace 1e-99 by a true 0 (same tip as in fmecagraph)
% 13/12/2011 help fixes (version 0.49951)
% 05/05/2014 add 'interp1' / compatible last Matlab versions (FMECAengine version 0.49952)
% 05/05/2014 accept mixed number of layers, print_png crops figures now
% 06/05/2014 add sim constructor to be used without OpenOffice (FMECAengine version 0.49955)
% 08/05/2014 add ODSpassthrough() with shorthands, automatic spanning (FMECAengine version 0.50)
% 05/05/2014 add mergeoutput, check html extensions (FMECAengine version 0.501)
% 09/05/2014 reverse change of 05/05/2014 isequaln is replaced by matcmp (not available in old Matlab codes) (FMECAengine version 0.5011)
% 09/05/2014 fix .ods extension when automatic inputs is used (FMECAengine version 0.5012)
% 10/05/2014 remove supplied fields with automatic inputs (FMECAengine version 0.5013)
% 05/04/2015 print profiles and kinetics as CSV files (using print_csv) (FMECAengine version 0.51)
% 19/10/2015 add layerid to restart section (FMECAengine version 0.52)
% 20/10/2015 fix layerid (previousres was not used) (FMECAengine version 0.521)
% 20/10/2015 propagates C0eq (FMECAengine version 0.522)
% 21/10/2015 set layerid and xlayerid (more robust) (FMECAengine version 0.523)
% 21/10/2015 the following rule is implemented in senspantankarC(): negative concentration, remove the layer (FMECAengine version 0.524)
% 24/10/2015 full implementation of senspatankar_restart (FMECAengine version 0.53)
% 30/11/2015 add general deletion enabling the addition of layers on the fly (FMECAengine version 0.54)
% 07/02/2016 transitory fork FMECAengine2 to manage open systems and complex flows
% 09/02/2016 fix ramdisk usage, modified fileinfo (noerror)
% 10/02/2016 add noplot
% 14/02/2016 fix the recovery of session name (RAMDISK) from data when simulation data are available, new properties, fix noplot
% 15-17/02/2016 RC of the scheduler, several developments and improvements to implement new features (version 0.60015)
% 18/02/2016 back step, no more use of 'nostructexpand' for propagation (implemented on 17/02/16), use argcheck/isnan2()
% 19/02/2016 fix schedule, add nohtml, add parentF and CF0 to fmecadb, fix the test fmecadb(1).(previousid).CF-r.CF(1)<eps when parentF is used
% 19/02/2016 optimized cache and fix the comparison of simulations
% 20/02/2016 first documented example for flows (version 0.60019)
% 05/03/2016 add CPi, CFi: concentrations at the interface, add savememory, add  enginesingle,enginerestart,enginedelete,enginesetoff (version 0.6023)
% 30/08/2017 fix CF0 in s(map(isim,iseries)).restart (version 0.61, major bug correction)

%% RAMDISK
persistent RAMDISK % usage RAMDISK.(session).(jobid).r
if isempty(RAMDISK), RAMDISK = struct([]); end
%% Fmecaengine version
versn = 0.60019; % official release
mlmver = ver('matlab');
extension = struct('Foscale','Fo%d%d','Kscale','K%d%d','ALT','%sc%d'); % naming extensions (associated to scaling)
prop2scale = struct('Foscale','regular_D','Kscale','regular_K'); % name of columns
ncol = 64; % number of reference colors for colormaps (note that used colors are linearly interpolated among ncol colors)
defaultautofmecamainfile = struct('nlayers',3,'nsteps',1); kwautofmecamainfile = {'make' 'constructor'}; % for default creation
autostepname = 'STEP%02d';

%% Check for a valid installation of the toolbox bioinfo
% if missing, graphs are not plotted
% next versions will switch to graphviz instead (http://www.graphviz.org/)
bioinfo_is_installed = ~isempty(find_path_toolbox('bioinfo'));

%% Default, if variables are defined in base their values are used as default values (to mimic a function usage as script)
defaultsession = autoprojectname(5,true);
default = struct('local','','inputpath','','outputpath','','fmecamainfile','','fmecadbfile','','fmecasheetname','',... properties that can overriden in base
                 'options',odeset('RelTol',1e-4,'AbsTol',1e-4,'Initialstep',1e-8,'Maxstep',1e3,'Maxorder',2),...
                 'nmesh',200,...
                 'nmeshmin',10,...
                 'headers',2,... number of header lines
                 'interp1','pchip',... interpolation method (added 05/05/2014)
                 'nograph',false,... if true, unable graphs
                 'noprint',false,... if true, unable prints
                 'nohtml',false,... if true, unable html file
                 'mergeoutput',false,... force the output to be merhed (added 08/05/2014)
                 'cls',false,... force clean screen
                 'database',struct([]),... database to be used with keys
                 'databaseheaders',1,... number of header lines for database
                 'enginesingle',@(S) senspatankar(senspatankar_wrapper(S)),...  engine for single step
                 'enginerestart',@(S)senspatankarC(senspatankar_wrapper(S)),... engine with restart section
                 'enginedelete',@(S) senspatankarC(senspatankar_wrapper(S)),... engine with deleted/added layers
                 'enginesetoff',@(S) setoffpatankar(senspatankar_wrapper(S)),...engine with periodic boundary condition
                 'regular_l','^l\d+m$',... regular expression to check l
                 'regular_D','^D\d+m2s$',... regular expression to check D
                 'regular_K','^KFP\d+kgm3kgm3$',... regular expression to check K
                 'regular_C','^CP\d+0kgm3$',... regular expression to check C
                 'print_l','l%dm',... l values
                 'print_D','D%dm2s',... D values
                 'print_K','KFP%dkgm3kgm3',... K values
                 'print_C','CP%d0kgm3',... C values
                 'print_L','lFm',... L value
                 'print_t','ts',... t value
                 'print_Bi','Binounit',... Bi value
                 'print_CF0','CF0',... initial concentration
                 'print_id','idusercode',...
                 'print_parent','parent',...
                 'print_inherit','inherit',...
                 'print_parentF','parentF',... % syntax 'id' or 'id1,id2,id3' inherit CF(t=0) from previous simulation, t: is relative time
                 'print_flowF','flowF',...       % inherit CF(t=0) from previous simulation, t: is relative time
                 'print_isstatic','isstatic',...
                 'print_SML','SMLkgm3',... SML valule
                 'maxwidth',24,... maximum column size for text cells (in HTML tables)
                 'severity',@(CF,SML) 100*99./max(100*SML./CF-1,0),...
                 'sample',@(x) prctile(x,[5 50 95]),...
                 'session', defaultsession...
                 ); kwdefault = {'noprint' 'nograph' 'noplot' 'ramdisk' 'ls' 'flush' 'delete' 'savememory'};
% Possible user override of default values by defining variables with similar name in workspace 'base' and char content
% recognized variables: local, inputpath, outputpath, fmecamainfile, fmecadbfile, fmecasheetname
vlist = fieldnames(default)';
for v=vlist(1:6)
    if isempty(default.(v{1})) && evalin('base',sprintf('exist(''%s'',''var'')',v{1}))
        dispf('WARNING: the value of ''%s'' is derived from the one defined in base, please check',v{1})
        uservarinbase = evalin('base',v{1});
        if ischar(uservarinbase), default.(v{1}) = uservarinbase; end
    end
end
iconfile = 'table.png'; % default icon for browser
iconpath = fullfile(find_path_toolbox('migration'),'media'); % expected path
if ~exist(fullfile(iconpath,iconfile),'file'),  iconpath = find_path_toolbox('migration'); end % alternative path
if ~exist(fullfile(iconpath,iconfile),'file'), iconpath = rootdir(mfilename('fullpath')); end
if ~exist(iconpath,'dir'), iconpath = rootdir(mfilename('fullpath')); end
% Default root directory (these definitions are obsolete and undesirable in opensource projects, TO BE CLEANED)
% The information listed in this section is still useful to locate previous works
if isempty(default.local)
    switch localname % according to the name of the machine (either Windows or Linux)
        case {'WSLP-OLIVIER2' 'WSLP-OLIVIER4' 'mol15.agroparistech.fr'}  % development platforms
            default.local = find_path_toolbox('migration'); %             %local = '\\ws-mol4\c$\data\olivier\Audrey_Goujon\Matlab';
            default.inputpath = filesep;
            default.outputpath = 'tmp';
        case 'WS-MOL4'                      % production platform (Win64)
            default.local = 'C:\Data\Olivier\Audrey_Goujon\Matlab';
        case 'mol10.agroparistech.fr'       % production platform (Linux64)
            default.local = '/home/olivier/Audrey_Goujon/Matlab';
        otherwise
            default.local = pwd;
    end
end
% Default files and folders (very generic)
if isempty(default.inputpath),      default.inputpath = 'inputs'; end  % relative path for input files
if isempty(default.outputpath),     default.outputpath = 'outputs'; end % relative path for output files
if isempty(default.fmecamainfile),  default.fmecamainfile = 'fmeca_demo3.ods'; end % file that describes scenarios to launch (only the spreadsheet 'sim' is used)
if isempty(default.fmecadbfile),    default.fmecadbfile = 'fmecabaseofconditions.mat'; end % file that lists all simulated conditions
if isempty(default.fmecasheetname), default.fmecasheetname = 'sim';  end

% argcheck
if nargin>1
    % previous 17/02/16
    %o = argcheck(varargin,default,kwdefault,'case','property','nostructexpand'); % to keep structure arguments such as data0 or data
    % after 17/02/16
    [otmp,remaintmp] = argcheck(varargin,struct('fmecamainfile',[]),'','case','property','nostructexpand'); % to keep structure arguments such as data0 or data
    o = argcheck(remaintmp,default,kwdefault,'case');
    o.fmecamainfile = otmp.fmecamainfile;
else
    o = argcheck(varargin,default,kwdefault,'case');
end

% === manage sessions in RAMDISK (basic functions: 'ls' 'flush' 'delete')
if o.ramdisk
    nforamdisk=whos('RAMDISK');
    dispf('FEMCAengine:: the RAMDISK contains ''%d'' sessions and uses %s',length(fieldnames(RAMDISK)),memsize(nforamdisk.bytes,5,'Bytes'))
    if (o.ls || o.flush || o.delete)
        if isempty(o.session) || strcmp(o.session,defaultsession), o.session = 'all'; end
        if ischar(o.session) && strcmpi(o.session,'all'), o.session = fieldnames(RAMDISK); end
        if ~iscell(o.session), o.session={o.session}; end
        o.session = o.session(:)';
        if ~iscellstr(o.session), error('property ''session'' must be a char or cell array of strings'), end
        for s=o.session
            if ~isfield(RAMDISK,s{1}), error('FMECAengine RAMDISK:: the session ''%s'' does not exist',s{1}), end
            idlist = fieldnames(RAMDISK.(s{1}))';
            nodetmp = RAMDISK.(s{1}); nodenfo = whos('nodetmp'); %#ok<NASGU>
            dispf('\tSESSION ''%s'' includes %d simulations (%s)',s{1},length(idlist)-1,memsize(nodenfo.bytes,4,'Bytes')); dispf(repmat('-',1,80))
            for id = idlist
                if o.ls && ~strcmp(id{1},'fmecadb')
                    nodetmp = RAMDISK.(s{1}).(id{1}).file; nodenfo = whos('nodetmp'); %#ok<NASGU>
                    dispf('\tSTEP=''%s''\t [%s, %s]\t%s',id{1},memsize(nodenfo.bytes,3,'b'),RAMDISK.(s{1}).(id{1}).date,RAMDISK.(s{1}).(id{1}).filename);
                end % ls
                if o.flush % RAMDISK content is flushed to disk
                    if strcmp(id{1},'fmecadb'), fmecadb = RAMDISK.(s{1}).(id{1}).file; save(RAMDISK.(s{1}).(id{1}).filename,'fmecadb')
                    else r = RAMDISK.(s{1}).(id{1}).file; save(RAMDISK.(s{1}).(id{1}).filename,'r') %#ok<NASGU>
                    end
                end % flush
            end % next id
            if o.ls, dispf(repmat('-',1,80)); end
            if o.delete, RAMDISK = rmfield(RAMDISK,s{1}); end
        end % next session
        return
    end % ls, flush, delete
end
% == end manage sessions

% Graphs
if ~o.noplot, close all, end
hgraph = [NaN NaN NaN NaN NaN NaN]; % dependence inheritance result pareto kinetics
if o.nograph
    o.noprint=true;
else
    delete(findall(0,'Tag','BioGraphTool')) % remove any previous graph
end

% check whether sample is a valid anonymous function
if ~isa(o.sample,'function_handle'), error('sample must be an anonymous function, e.g.: @(x)prctile(x,[5,50,95])'); end
try
    o.sample(1);
catch errmsg
    dispf('WARNING:: sample generated the following error:\n\t%s\n%s\n\t==>To prevent further errors, it is replaced by @(x)median(x).',errmsg.identifier,errmsg.message)
    o.sample = @(x)median(x);
end

%% load FMECA main file (simulation definition): only ODS file is accepted for compatibility with LINUX (convert any XLS file to ODS if required)
clc
if ~bioinfo_is_installed
    dispf('WARNING: disabled features:\n\tThe toolbox ''bioinfo'' is not installed on your computer.\n\tPlots will be available but the graphs will be disabled.\n\tNext versions will propose <a href="http://www.graphviz.org/">GRAPHIZ</a> as an alternative.\n')
end
if ischar(o.fmecamainfile)
    dispf('\t%s (v.%0.3g) - %s\n\t%s in %s\n\tINRA\\Olivier Vitrac\n',mfilename,versn,datestr(now),o.fmecamainfile,fullfile(o.local,o.inputpath))
else
    dispf('\t%s (v.%0.3g) - %s\n\tINRA\\Olivier Vitrac\n',mfilename,versn,datestr(now))
    if isstruct(o.fmecamainfile) && isfield(o.fmecamainfile,'session') && ~isempty(o.fmecamainfile(1).session) && ischar(o.fmecamainfile(1).session)
        o.session = o.fmecamainfile(1).session;
        dispf('\tset the active session to ''%s''',o.session)
    end
end
if exist(fullfile(o.local,o.outputpath,o.fmecadbfile),'file')
    load(fullfile(o.local,o.outputpath,o.fmecadbfile)) % load variable fmecadb
    dispf('\nFMECA database of previous simulations loaded:')
    fileinfo(fullfile(o.local,o.outputpath,o.fmecadbfile))
    dispf('\t %d simulations restored',length(fieldnames(fmecadb)))
elseif o.ramdisk && isfield(RAMDISK,o.session)
    if isfield(RAMDISK.(o.session),'fmecadb')
        fmecadb = RAMDISK.(o.session).fmecadb.file;
        dispf('\nThe FMECA database restored from session ''%s'' in RAMDISK',o.session)
        dispf('\t %d simulations restored',length(fieldnames(fmecadb)))
    else
        dispf('\nThe FMECA database is corrupted in RAMDISK, try to start from a cleaned one')
        fmecadb = struct([]); % clear any previous database in workspace
    end
else
    fmecadb = struct([]); % clear any previous database in workspace
end
if ischar(o.fmecamainfile)
    dispf('\nLoad FMECA definition file ''%s'' located in ''%s''',o.fmecamainfile,fullfile(o.local,o.inputpath))
elseif isempty(fmecadb), dispf('\n no data in the current session')
else dispf('\n reuse data from a previous instance of fmecaengine')
end

%%% ======================  automatic fmecamainfile / 06/05/14
if iscell(o.fmecamainfile) % new syntax 
    if ODSpassthrough(), return, end
end    
%%% ======================  

if ischar(o.fmecamainfile)
    if ~exist(fullfile(o.local,o.inputpath,o.fmecamainfile),'file'), error('the FMECA file definition ''%s'' does not exist in ''%s''',o.fmecamainfile,fullfile(o.local,o.inputpath)), end
    [~,nfodata] = fileinfo(fullfile(o.local,o.inputpath,o.fmecamainfile),'',false);
    data = loadods(fullfile(o.local,o.inputpath,o.fmecamainfile),'sheetname',o.fmecasheetname,'headers',o.headers,'structarray',true);
elseif isstruct(o.fmecamainfile)
    data = o.fmecamainfile;
    %if isfield(data,'session') && ~isempty(data(1).session) && ischar(data(1).session)
    %    o.session = data(1).session;
    %    dispf('\tset the active session to ''%s''',o.session)
    %end %code commented on 14/02/2016
    [data(cellfun('isempty',{data.(o.print_parent)})).(o.print_parent)] = deal(NaN); % replace '' by NaN values in Parent (default behavior from original ods files)
    if isfield(data,o.print_parentF) % added version 0.6
        [data(cellfun('isempty',{data.(o.print_parentF)})).(o.print_parentF)] = deal(NaN); % replace '' by NaN values (default behavior from original ods files)
    end
    if isfield(data,o.print_isstatic) % added version 0.6
        [data(cellfun('isempty',{data.(o.print_isstatic)})).(o.print_isstatic)] = deal(false); % replace '' by false values
    end    
    if isfield(data,o.print_inherit)
        [data(cellfun('isempty',{data.(o.print_inherit)})).(o.print_inherit)] = deal(NaN); % replace '' by NaN values (default behavior from original ods files)
    end
    o.fmecamainfile = o.inputpath; % even if a structure is used, a filaname with an extension .ods is required
    [~,~,extods]=fileparts(o.fmecamainfile); if isempty(extods), o.fmecamainfile=sprintf('%s.ods',o.fmecamainfile); end % added 09/05/2014
    o.inputpath = '--> script: ';
    nfodata = sprintf('%s:%s',regexprep(char(regexp(evalc('whos(''data'')'),'data.*','match')),{'\s{2,}' '(\d*) struct'},{' ','struct array ($1 bytes)'}));
else
    error('fmecamainfile must be a valid filename or a structure')
end
if nargout>1, data0out = data; end % store the initial state of data
if ~exist(fullfile(o.local,o.outputpath),'dir'), mkdir(o.local,o.outputpath), end % create the output directory if it does not exist

%% Check whether the database is consistent with prescribed rules
%   Id must be strings with [A-Za-Z0-9_] characters
%   
ndata = length(data);           % number of lines (simulations) in the FMECA file
if ~isfield(data,o.print_id), error('the column ''%s'' is missing',o.print_id); end
idusercode = {data.(o.print_id)}; % collect all id
dispf('\t\t\t==> %d simulation definitions found\n',ndata)
% Check that id are strings
if ~iscellstr(idusercode), error('All id must be a string in ''%s''',fullfile(o.local,o.inputpath,o.fmecamainfile)); end
%
% Check that all id are unique
[dup,idup,ndup] = findduplicates(idusercode);
if ~isempty(dup)
    dispf('\n\nERROR in FMECA file ''%s'' located in ''%s''',o.fmecamainfile,fullfile(o.local,o.inputpath))
    cellfun(@(idr,nr) dispf('\t''%s'' is repeated %d times',idr,nr), dup,num2cell(ndup,2))
    dispf('By discarding headers (first raw of data = index 1), redundant rows are:')
    cellfun(@(i,id) dispf('\tcheck line %d (%s)',i,id),num2cell(idup,2),idusercode(idup)')
    error('Please remove repeated steps or update idusercode, check your file and restart %s',mfilename)
end
%
% ==== Check that all parents have been defined
if ~isfield(data,o.print_parent), error('the column ''%s'' is missing',o.print_parent); end
parent = {data.(o.print_parent)};
isvalidparent = cellfun(@(x) ~isnan(x(1)),parent);
missingparents = setdiff(parent(isvalidparent),idusercode);
if ~isempty(missingparents)
    dispf('\n\nERROR in FMECA file ''%s'' located in ''%s''',o.fmecamainfile,fullfile(o.local,o.inputpath))
    dispf('\tmissing parent simulation ''%s''\n',missingparents{:})
    error('Inheritance of simulations results (i.e. dependent simulations)\ncan work only if required parents have been defined.\nCheck your file and restart %s',mfilename)
end
parent(~isvalidparent) = {''}; % empty strings are required for orphans
[data.(o.print_parent)] = deal(parent{:}); % updating (required for copying nodes)
%
% ==== parentF column (not mandadory, default value = NaN) - version 0.6
if isfield(data,o.print_parentF)
    parentF = {data.(o.print_parentF)}';
    iparentF = cell(size(parentF));
    parentF(cellfun(@isnumeric,parentF))={''}; % empty strings are required for orphans
    ndatawithparentF = cellfun(@length,parentF);
    idatawithparentF = find(ndatawithparentF>0);
    if any(idatawithparentF)
        parentF = cellfun(@(t) expandtextaslist(t,'\s*[,;\|]+\s*')',parentF,'uniformoutput',false);
        missingparentsF = setdiff([parentF{idatawithparentF}],idusercode);
        if ~isempty(missingparentsF)
            idatanum = expandmat(ndatawithparentF,ndatawithparentF);
            dispf('\n\nERROR in FMECA file ''%s'' located in ''%s''',o.fmecamainfile,fullfile(o.local,o.inputpath))
            for imissing=1:length(missingparentsF)
                dispf('[line %d/%d]\tmissing parentF object ''%s''\n',idatanum(imissing),length(parentF),missingparentsF{imissing})
            end %idatawithparentF
            error('Inheritance of flows (i.e. dependent simulations)\ncan work only if related simulations have been defined.\n Check your file and restart %s',mfilename)
        end % missing parentF
        for idata = idatawithparentF(:)'
            if iscell(parentF{idata})
                iparentF{idata} = cellfun(@(t)find(ismember(idusercode,t)),parentF{idata});
            else
                iparentF{idata} = ismember(idusercode,parentF{idata});
            end
        end
        [data.(o.print_parentF)] = deal(parentF{:}); % updating (required for copying nodes)
    else
        data = rmfield(data,(o.print_parentF)); 
    end % idatawithparentF
else
    [parentF,iparentF] = deal(repmat({''},size(parent)));
end
%
% ==== inherit column (not mandadory, default value = NaN)
if isfield(data,o.print_inherit)
    inherit = {data.(o.print_inherit)};
    isvalidinherit = cellfun(@(x) ~isnan(x(1)),inherit);
    missinginherit = setdiff(inherit(isvalidinherit),idusercode);
    if ~isempty(missinginherit)
        dispf('\n\nERROR in FMECA file ''%s'' located in ''%s''',o.fmecamainfile,fullfile(o.local,o.inputpath))
        dispf('\tmissing inherited objects ''%s''\n',missinginherit{:})
        error('Inheritance of inputs (i.e. non-dependent simulations)\ncan work only if related simulations have been defined.\n Check your file and restart %s',mfilename)
    end
    inherit(~isvalidinherit) = {''}; % empty strings are required for orphans
    [data.(o.print_inherit)] = deal(inherit{:}); % updating (required for copying nodes)
    if ~any(isvalidinherit), data = rmfield(data,(o.print_inherit)); end % clean the inputs if the field is not required
else
    inherit = repmat({''},size(parent));
end
% ==== weight column (not mandadory, default value = {[1]}) - version 0.6
if isfield(data,o.print_flowF)
    flowF = {data.(o.print_flowF)}; % cell array
    isvalidflowF = cellfun(@(x) isnumeric(x) && ~isnan(x(1)),flowF);
    flowF(~isvalidflowF) = {1}; % default values are required for orphans
    [data.(o.print_flowF)] = deal(flowF{:}); % updating (required for copying nodes)
    if ~any(isvalidflowF), data = rmfield(data,(o.print_flowF)); end % clean the inputs if the field is not required
else
    flowF = repmat({1},size(parent));
end
%
% ==== isstatic column (not mandadory, default value = false)
if isfield(data,o.print_isstatic)
    isstatic = {data.(o.print_isstatic)};
    isvalidisstatic = (cellfun(@isnumeric,isstatic) | cellfun(@islogical,isstatic)) & cellfun(@isscalar,isstatic);
    [data(~isvalidisstatic).(o.print_isstatic)] = deal(false);
    isstatic = [data.(o.print_isstatic)]>0; % boolean array, since NaN>0 returns false, all NaN are replaced by false
    if ~any(isvalidisstatic), data = rmfield(data,(o.print_isstatic)); end % clean the inputs if the field is not required
else
    isstatic = false(size(parent));
end
%
% ==== CF0 column (not mandadory, default value = 0)
if isfield(data,o.print_CF0)
    CF0 = {data.(o.print_CF0)};
    isvalidCF0 = cellfun(@isnumeric,CF0) & cellfun(@isscalar,CF0);
    [data(~isvalidCF0).(o.print_CF0)] = deal(0);
    CF0 = [data.(o.print_CF0)]; % numeric array, since NaN>0 returns false, all NaN are replaced by false
    if ~any(isvalidCF0), data = rmfield(data,(o.print_CF0)); end % clean the inputs if the field is not required
else
    CF0 = false(size(parent));
end
%
% Check that all characters for id and parent are valid
isbad = ~cellfun('isempty',regexp(idusercode,'(^\d)|([^A-Za-z0-9_])'));
if any(isbad)
    dispf('\n\nERROR in FMECA file ''%s'' located in ''%s''',o.fmecamainfile,fullfile(o.local,o.inputpath))
    dispf('\tbad characters in id ''%s''\n',idusercode{isbad})
    error('Update the identifiants and restart %s\n(accepted characters are ''A-Z'', ''a-z'', ''0-9'' and ''_''. Note that digits are not allowed as first character)',mfilename)
end

%% INPUT VALUES (without any automatic modification)
ndata0 = ndata;
hgraph(1) = fmeca2graph; % input graph
inputhtml = fmeca2html('filenamemodifyer','.input','links',false);


%% KEYS INTERPRETATION (IF ANY) - added starting from version 0.34
% Define database
if isempty(o.database), o.database = struct('filename',fullfile(o.local,o.inputpath,o.fmecamainfile),'headers',o.databaseheaders); end
if ischar(o.database)
    o.database = struct('filename',o.database,'headers',o.databaseheaders);    
    if ~exist(o.database.filename,'file'), o.database.filename = fullfile(o.local,o.inputpath,o.database.filename); end
end

% Keep a copy of Foscale and Kscale (Foscalecopy and Kscalecopy for legends)
if isfield(data,'Foscale'), [data.Foscalecopy] = deal(data.Foscale); end
if isfield(data,'Kscale'), [data.Kscalecopy] = deal(data.Kscale); end

% Properties with possible key syntax (see key2key() for more details)
osamplesize = length(o.sample(1));
oprop = fieldnames(o); f = fieldnames(data);
opropregular = oprop(~cellfun('isempty',regexp(oprop,'regular_.*'))); % properties defined by regular expressions
keyprop = f(any(~reshape(cellfun('isempty',uncell(cellfun(@(f) regexp(f,cellfun(@(p) o.(p),opropregular,'UniformOutput',false)),...
                                 f,'UniformOutput',false))),length(opropregular),length(f)),1));
keyprop = [{'Kscale' 'Foscale'} keyprop' {o.print_Bi o.print_L o.print_SML o.print_t}]; % list of eligible properties for keys
for kp = keyprop % must start with Kscale and Foscale before K and D to enable union operator to work
    if isfield(data,kp{1})
        indkey = find(cellfun(@(x)ischar(x),{data.(kp{1})}));
        if any(indkey)
            for irow=indkey
                keycode = data(irow).(kp{1});
                dispf('FMECAENGINE interpreter at LINE %d - COLUMN ''%s''\n\t''%s''',irow,kp{1},keycode)
                [keyval,o.database] = key2key(o.database,keycode);
                nkeyval = length(keyval);
                if ~isempty(regexp(kp{1},o.regular_D, 'once')) % code for a D value
                    % before 0.43
                    %keymin = min(keyval); keymax = max(keyval); keyval = median(keyval(~isnan(keyval)));
                    % after 0.43
                    keyval = keyval(~isnan(keyval));
                    if numel(keyval)>osamplesize % one->many returns more values than the requested sample (then sampling is applied)
                        keysample = o.sample(keyval); if isempty(keysample), error('no value returned after sampling for ''%s''',keycode); end
                    else % initial set of values is smaller than the requested sample
                        keysample = keyval;
                    end
                    keyval = keysample(nearestpoint(median(keysample),keysample)); keysample = setdiff(keysample,keyval);
                    if any(keysample)
                        if ~isfield(data,'Foscale')
                            f=fieldnames(data); [data.Foscale] = deal(NaN);
                            data(irow).Foscale=keysample/keyval; data = orderfields(data,[{'Foscale'};f]);
                        else
                            data(irow).Foscale=union(data(irow).Foscale(~isnan(data(irow).Foscale)),keysample/keyval);
                        end
                    end
                    calcstat = true;
                elseif ~isempty(regexp(kp{1},o.regular_K, 'once')) % code for a K value
                    % before 0.43
                    %keymin = min(keyval); keymax = max(keyval); keyval = median(keyval(~isnan(keyval)));
                    % after 0.43
                    keyval = keyval(~isnan(keyval));
                    if numel(keyval)>osamplesize % one->many returns more values than the requested sample (then sampling is applied)
                        keysample = o.sample(keyval); if isempty(keysample), error('no value returned after sampling for ''%s''',keycode); end
                    else % initial set of values is smaller than the requested sample
                        keysample = keyval;
                    end
                    keyval = keysample(nearestpoint(median(keysample),keysample)); keysample = setdiff(keysample,keyval);
                    if any(keysample)
                        if ~isfield(data,'Kscale')
                            f=fieldnames(data); [data.Kscale] = deal(NaN);
                            data(irow).Kscale=keysample/keyval; data = orderfields(data,[{'Kscale'};f]);
                        else
                            data(irow).Kscale=union(data(irow).Kscale(~isnan(data(irow).Kscale)),keysample/keyval);
                        end
                    end
                    calcstat = true;
                elseif ~ismember(kp{1},{'Kscale' 'Foscale'}) % other properties
                    keyval = mean(keyval(~isnan(keyval)));
                    calcstat = true;
                else
                    calcstat = false;
                end
                if isempty(keyval), keyval=NaN; end % empty values are set to NaN (as does by loadods)
                data(irow).(kp{1}) = keyval; % update numeric value
                if nkeyval>1
                    if calcstat, dispf('\tinterpreted as %0.4g (statistical result from %d values)',data(irow).(kp{1}),nkeyval)
                    else         dispf('\tinterpreted as %d values',nkeyval)
                    end
                else             dispf('\tinterpreted as %0.4g (scalar value)',data(irow).(kp{1}))
                end
            end % for irow
        end % any(indkey)
    end % isfield
end % for kp

%% PROPAGATE FOSCALING (multi-level trees) - added starting from version 0.28
% Note that these properties are not inheritable (scaling must be performed before any inheritance)
newroots = false; allreadyinherited = false;
if isfield(data,'Foscale')
    ApplyInheritanceStrategy(true); % forced inheritance before propagating scaling (to populate Foscale)
    allreadyinherited = true;
    newroots = PropagateScale('Foscale');
    if isfield(data,'Foscalecopy'), data = rmfield(data,'Foscalecopy');  end
end
if isfield(data,'Kscale')
    if ~allreadyinherited
        ApplyInheritanceStrategy(true); % forced inheritance before propagating scaling (to populate Kscale)
    end
    allreadyinherited = false;
    newroots = newroots | PropagateScale('Kscale');
    if isfield(data,'Kscalecopy'), data = rmfield(data,'Kscalecopy'); end
else
    allreadyinherited = false;
end
if ~allreadyinherited, ApplyInheritanceStrategy(newroots); end

%% CREATION OF STATIC RESULTS (version 0.6 and later)
% NOTE THAT STATIC RESULTS ARE CREATED VERY EARLY AND ONLY IN fmecadb (there is no file virtual or not attached)
% Currently only CF (with CF=CF0 by definition) is propagated
if any(isstatic)
    for idata = find(isstatic)
        fmecadb(1).(data(idata).(o.print_id)) = struct(...
            'isstatic',true,...
            'parent','',...  by definition for a static step
            'inherit','',... by definition for a static step
            'path',[],...
            'isterminal',false,... by definition for a static step (to be used by dependent simulations)
            't',NaN,...
            'CF',CF0(idata),... CF=CF0 by definition of a static step
            'SML',NaN,... by definition of a static step
            'dCF',0,... since CF=CF0
            'CPi',NaN,... concentration at the interface (P side) - updated on 05/03/2016
            'CFi',NaN,... concentration at the interface (F side) - updated on 05/03/2016
            'nfo','static object (no mass transfer)',...
            'session',o.session);
    end % next idata
end

%% UPDATE FLOW PARAMETERS IF STEPS HAS BEEN AUTOMATICALLY ADDED (version 0.6 and later)
if ndata>ndata0
    parentF  = argpad(parentF,ndata,[],{''});
    iparentF = argpad(iparentF,ndata,[],{[]});
    istatic  = argpad(istatic,ndata,[],false);
    flowF    = argpad(flowF,ndata,[],{[]});
    CF0      = argpad(CF0,ndata,[],0);
end

%% SCHEDULE SIMULATIONS USING parentF (version 0.6 and later)
% ALGORITHM (pseudo-recursion to save memory and for efficiency)
% if no parentF defined -> pass through
% as soon as all parentF are calculated -> pass through
% for other cases: run fmecaengine2() when no parentF or parentF has been calculated
hasparentF = ~cellfun(@isempty,parentF); % true if is has a parentF
if any(hasparentF) % no pass through
    idataparentF = find(hasparentF);
    [iduserdone,isparentFdone] = deal(false(ndata,1));
    scheduling = true; iter=0; nidavailable_previous = 0;
    while scheduling % main scheduling loop
        iter = iter + 1; idavailable = fieldnames(fmecadb); nidavailable = length(idavailable);
        if (iter>1) && (nidavailable==nidavailable_previous) % no new result
            scheduling = false; % -> no more improvement (no infinite loop, not all results may have been calculated)
        else % new results have been calculated
            nidavailable_previous = nidavailable;
            for idata = idataparentF(:)', isparentFdone(idata) = all(ismember(parentF{idata},idavailable)); end
            for idata = 1:ndata, iduserdone(idata) = ismember(idusercode{idata},idavailable); end
            if all(isparentFdone(idataparentF))
                scheduling = false; %-> pass through, all parentF are available
            else % recursion section: run simulation and refresh list of nodes available
                fmecadb = fmecaengine2('fmecamainfile',data(~hasparentF | isparentFdone),rmfield(o,{'ls','flush','delete'}));
            end % endif all(hasparentF(idataparentF))
        end % endif nidavailable==nidavailable_previous
    end % endwhile
end %endif any(hasparentF)

%% INHERITANCE PLOTS
if ~o.noplot
    hgraph(2) = fmeca2graph('ref',1:ndata0,'prop',o.print_inherit,'color',rgb('Teal'),'colorref',rgb('FireBrick'),'textcolor',[1 1 1]);
    hgraph(1) = fmeca2graph('ref',1:ndata0); % output graph
end

%% PARENT: Build the simulation tree and related dependences (inheritance of both simulations results and inputs)
[simseries,~,map] = buildmarkov(idusercode,{data.(o.print_parent)},'sort','ascend'); % build all possible paths to match dependences (start with shortest ones)
nseries = length(simseries);   % number of series of independent simulations
nsimtot = length(unique(map(map>0)));   % total number of simulations
countmax = length(find(map>0));

%% Prepare simulations (do not launch them)
% This section i) defines simulation scenarios and ii) manages required updates

% Some constants
days = 24*3600;    % s
s0 = senspatankar; % prototype of simulation object (constructor)
s0.options = o.options; % user override
s0.nmesh = o.nmesh;     % user override
s0.nmeshmin = o.nmeshmin; % user override
screen = '';       % screen backstore (for text animation)
tstart = clock;    % starting time (to compute elpased time)

% check all fields related to layers (spread over several columns/fields)
% Regular expressions are used to identify l, D, KFP anf CP0 values
% As a result, the same code can handle an arbitrary number of layers (note that numbers need to be consecutive
datafields = fieldnames(data); % all fields in spreadheet
nlfield = length(find(~cellfun('isempty',regexp(datafields,o.regular_l,'tokens')))); % number of fields l#m where #=1,2...
if nlfield<1, error('unable to identify the column/field for thikcknesses, l#m where #=1,2...'), end
nDfield = length(find(~cellfun('isempty',regexp(datafields,o.regular_D,'tokens')))); % number of fields D#m2s where #=1,2...
if nDfield<1, error('unable to identify the column/field for diffusion coefficients: D#m2s where #=1,2'), end
nKfield = length(find(~cellfun('isempty',regexp(datafields,o.regular_K,'tokens')))); % number of fields KFP#kgm3kgm3 where #=1,2...
if nKfield<1, error('unable to identify the column/field for partition coefficients: KFP#kgm3kgm3 where #=1,2'), end
nCfield = length(find(~cellfun('isempty',regexp(datafields,o.regular_C,'tokens')))); % number of fields CP#0kgm3 where #=1,2...
if nCfield<1, error('unable to identify the column/field for partition coefficients: CP#0kgm3 where #=1,2'), end

% Build input objects (structure array s) for all simulations and setup all corresponding flags
% NOTE that data and s have a different purpose: data will be used for display whereas s is used to launch simulations
%      CONSEQUENCES
%       i) field names used in s can differ from data, the structure s follow the requirements of the solver (senspatankarC() and its many variants)
%      ii) possibly fields removed from data (CF0, isstatic...) are restored at this stage
alreadydone = false(ndata,1); % flag, true if the simulation was already set
s = repmat(s0,ndata,1);  % input objects (with default constructor)
setoff = false(ndata,1); % flag, true for a simulation that is a setoff
action = zeros(size(map)); % table of actions (0=nothing to do, 1=to be created, 2=to be updated due to changes, 3=to be updated due to dependences)
count = 0;         % scenario counter
% fmecadb include fields which are not required for comparison (list them here, update if needed)
fmecadbfieldsnotconsidered = @(CPdbfields) [{'parent', 'parentF', 'inherit','path','isterminal','isstatic','restart','CF0','CF','dCF','t','SML'} CPdbfields];
% do for all series
for iseries = 1:nseries  % Main loop on each series of independent simulations (i.e. paths through trees)
    nsim = length(simseries{iseries}); % number of simulations in the current tree path (i.e. chain of simulations)

    for isim = 1:nsim    % Loop on dependent simulations
    
        currentid = simseries{iseries}{isim}; % id matching iseries and isim
        currentresfile = fullfile(o.local,o.outputpath,sprintf('%s.mat',currentid)); % result file (incl. full path)
        count = count + 1; % counter
        
        % Check dependences and propagate inputs inheritance
        if isim==1 % no dependence
            screen = dispb(screen,'[%d/%d (%d)]\t%s\t no dependence found...',count,countmax,nsimtot,currentid);
            d = data(map(isim,iseries)); % data to be simulated
        else % dependent simulation
            % all empty fields (or with NaN) in FMECA file are replaced by their respective values in parent
            dparent = data(map(isim,iseries)).(o.print_parent);
            d = argcheck(data(map(isim,iseries)),data(map(isim-1,iseries)),'','NaNequalmissing','case');
            d.(o.print_parent) = dparent;
            data(map(isim,iseries)) = d; % propagate inheritance
            screen = dispb(screen,'[%d/%d (%d)]\t%s\t dependent on ''%s''...',count,countmax,nsimtot,currentid,simseries{iseries}{isim-1});
        end
        % fix constraint data
        if isfield(d,o.print_isstatic) && isnan(d.(o.print_isstatic)), d.(o.print_isstatic) = false; end % protect flag from being NaN (no test on NaN)
        if isfield(d,o.print_CF0) && isnan(d.(o.print_CF0)), d.(o.print_CF0) = 0; end % set 0 from being NaN (no test on NaN)
        
        if ~alreadydone(map(isim,iseries)) % simulation is unset or static
            % Simulation setup (accept an arbitrary number of layers)
            s(map(isim,iseries)).isstatic = false;
            s(map(isim,iseries)).l  = arrayfun(@(i)d.(sprintf(o.print_l,i)),1:nlfield); % thicknesses
            s(map(isim,iseries)).k  = arrayfun(@(i)d.(sprintf(o.print_K,i)),1:nKfield); % partition coefficients
            s(map(isim,iseries)).D  = arrayfun(@(i)d.(sprintf(o.print_D,i)),1:nDfield); % diffusion coefficients
            s(map(isim,iseries)).C0 = arrayfun(@(i)d.(sprintf(o.print_C,i)),1:nCfield);  % initial concentrations
            nlayers = [ find(~isnan(s(map(isim,iseries)).C0),1,'last') % negative concentrations are accepted
                find(~isnan(s(map(isim,iseries)).l) & s(map(isim,iseries)).l>0,1,'last') % only non-NaN and positive values are accepted
                find(~isnan(s(map(isim,iseries)).D) & s(map(isim,iseries)).D>0,1,'last')
                find(~isnan(s(map(isim,iseries)).k) & s(map(isim,iseries)).k>0,1,'last') ]; % layers are indexed from 1 to nlayers
            if min(nlayers)~=max(nlayers), error('Data (C0, l, D and KFP) are not consitent, please check and restart %s',mfilename), end
            nlayers = min(nlayers);
            for eachproperty = {'l' 'C0' 'k' 'D'}
                s(map(isim,iseries)).(eachproperty{1}) = s(map(isim,iseries)).(eachproperty{1})(1:nlayers); % only valid layers are considered
            end
            s(map(isim,iseries)).L = sum(s(map(isim,iseries)).l)/d.(o.print_L); %BUG fixed 27/04/11 .../data(isim).(o.print_L);
            s(map(isim,iseries)).t = linspace(0,sqrt(2*d.(o.print_t)),500).^2;
            % Biot and setoff (detected as negative Bi value, if any)
            s(map(isim,iseries)).Bi = d.(o.print_Bi); % note that it should be related to the most resistive thickness
            if s(map(isim,iseries)).Bi<0, s(map(isim,iseries)).Bi = 0; setoff(map(isim,iseries)) = true; else setoff(map(isim,iseries)) = false; end
            % initial concentration in the food (version 0.6 and later, to be used with flows or if the step has no parent)
            if isfield(d,o.print_CF0), s(map(isim,iseries)).CF0 = d.(o.print_CF0); else s(map(isim,iseries)).CF0 = NaN; end
            % isstatic
            if isfield(d,o.print_isstatic), s(map(isim,iseries)).isstatic = d.(o.print_isstatic); else s(map(isim,iseries)).isstatic=false; end
            % validate the definition
            alreadydone(map(isim,iseries)) = true;
            % check inheritance from a static value (applied) - version 0.6 and later
            if isim>1 && isstatic(map(isim-1,iseries))
                s(map(isim,iseries)).CF0 = s(map(isim-1,iseries)).CF0; %currently only CF0 can be propagated from a static step
            end
        end
        
        % Check whether a simulation already exist (as MAT file and within the metadatabase)
        % if yes test whether the simulation conditions has been modified
        % (comparisons are based on s while discarding fields: parent','path','isterminal','restart')
        if o.ramdisk %(less control)
            if isfield(fmecadb,currentid) % the simulation result is known
                if isfield(fmecadb.(currentid),'isstatic') && fmecadb.(currentid).isstatic
                    screen = dispb(screen,'[%d/%d (%d)]\t%s\t is a static simulation\n(to restart this simulation, remove the entry from RAMDISK session ''%s'')',count,countmax,nsimtot,currentid,o.session);
                else
                    CPdbfields = uncell(regexp(fieldnames(fmecadb.(currentid)),'^CP\d+','match'),[],[],true)'; % added 28/10/11
                    if structcmp(s(map(isim,iseries)),fmecadb.(currentid),fmecadbfieldsnotconsidered(CPdbfields)) % compare simulation parameters
                        screen = dispb(screen,'[%d/%d (%d)]\t%s\t already available in RAMDISK session ''%s''\n(to restart this simulation, remove the entry from RAMDISK)',count,countmax,nsimtot,currentid,o.session);
                    else % conditions changed
                        action(isim,iseries) = 2;        % simulation set to be updated
                        action(isim+1:nsim,iseries) = 3; % all dependent simulations set to 3
                    end                    
                end
            else % does not exist
                action(isim,iseries) = 1;        % simulation to create
                action(isim+1:nsim,iseries) = 3; % all dependent simulations set to 3
            end
        else % default behavior (very strict control)
            if exist(currentresfile,'file') && isfield(fmecadb,currentid) % the simulation result is known
                CPdbfields = uncell(regexp(fieldnames(fmecadb.(currentid)),'^CP\d+','match'),[],[],true)'; % added 28/10/11
                if structcmp(s(map(isim,iseries)),fmecadb.(currentid),fmecadbfieldsnotconsidered(CPdbfields)) % compare simulation parameters
                    screen = dispb(screen,'[%d/%d (%d)]\t%s\t already available\n(to restart this simulation remove the file ''%s'')',count,countmax,nsimtot,currentid,currentresfile);
                    if ~exist(regexprep(currentresfile,'\.mat$','.pdf','ignorecase'),'file') || ~exist(regexprep(currentresfile,'\.mat$','.png','ignorecase'),'file')
                        action(isim,iseries) = 4; % simulation results present by PDF and PNG files are missing
                    end
                else % conditions changed
                    action(isim,iseries) = 2;        % simulation set to be updated
                    action(isim+1:nsim,iseries) = 3; % all dependent simulations set to 3
                end
            else % does not exist (file or simulation)
                if isfield(fmecadb,currentid) && isfield(fmecadb.(currentid),'isstatic') && fmecadb.(currentid).isstatic
                    screen = dispb(screen,'[%d/%d (%d)]\t%s\t is a static simulation\n(to restart this simulation, remove the entry from RAMDISK session ''%s'')',count,countmax,nsimtot,currentid,o.session);
                else % not static, then it does not exist
                    action(isim,iseries) = 1;        % simulation to create
                    action(isim+1:nsim,iseries) = 3; % all dependent simulations set to 3
                end
            end %if exist file
        end % ramdisk
       
        
    end % Loop on dependent simulations
    
end %main loop on each series of independent simulations            

%% Launch simulations, save results and generate requested outputs
if any(action(:)) && ~o.noplot, hfig = figure; else hfig = NaN; end
actionmessage = {
    'nothing to do (simulation up to date)'
    'new simulation running'
    'simulation updating due to changes'
    'simulation updating due to dependences'
    'regenerating PDF and PNG'
    }; % corresponding to action+1 values
alreadydone = false(ndata,1) | isstatic(:); % flag, true if the simulation was already launched
% relax all constraints if savememory is used
if o.ramdisk && o.savememory && isstruct(RAMDISK) && isfield(RAMDISK, o.session)
    for idata=1:ndata
        alreadydone(idata) = isfield(fmecadb,idusercode{idata}) && isfield(RAMDISK.(o.session),idusercode{idata}); 
    end
end
% end  alreadydone

[count,simcount] = deal(0) ;  % scenario and simulation counters
for iseries = 1:nseries  % Main loop on each series of independent simulations (i.e. paths through trees)
    nsim = length(simseries{iseries}); % number of simulations in the current tree path (i.e. chain of simulations)
    
    for isim = 1:nsim    % Loop on dependent simulations
        
        count = count + 1; % counter
        
        % check whether a new result has to to be calculated
        if action(isim,iseries) && ~alreadydone(map(isim,iseries)) % a new simulation needs to be created or updated
            
            % current id and msg
            currentid = simseries{iseries}{isim}; % id matching iseries and isim
            %currentresfile = fullfile(o.local,o.outputpath,sprintf('%s.mat',currentid)); % result file (incl. full path)
            simcount = simcount + 1;
            msg = actionmessage{action(isim,iseries)+1};
            
            if action(isim,iseries)<4 % simulation to start, restart, update
            
                % Manage dependence by loading previous results if required
                if (isim==1) || isstatic(map(isim-1,iseries)) % no dependence (root node, or static node)
                    [previousfile,previousid] = deal(''); % no previous simulation
                    previousres = struct([]);
                else % dependence (load previous results)
                    previousid = simseries{iseries}{isim-1};
                    previousfile = fullfile(o.local,o.outputpath,sprintf('%s.mat', previousid));
                    if o.ramdisk
                        previousres(1).r = RAMDISK.(o.session).(previousid).file;
                        if ischar(previousres(1).r)
                            error('FMECAengine:: node ''%s'' has been cleared from session ''%s'' with message:\n-->\t''%s''',currentid,o.session,previousres(1).r)
                        end
                    else
                        previousres  = load(previousfile); % load previous simulation results
                    end
                end
                
                % Manage parentF for flow simulation (simple inheritance, only CF is transferred)
                parentidF = parentF{map(isim,iseries)};
                if ~isempty(parentidF) % currently only one parentF is accepted
                    if ~isempty(fmecadb) && isfield(fmecadb,parentidF{1})
                        s(map(isim,iseries)).CF0 = fmecadb.(parentidF{1}).CF; % one single parent at this stage
                    else
                        error('FMECAengine bad reference %s=''%s'' for the node ''%s'' because the node ''%s'' has not been yet calculated',o.print_parentF,parentidF,currentid,parentidF)
                    end
                end
                
                % simulation (main job)
                t0 = clock;
                if isempty(previousres) % simulation without using a previous profile as initial solution
                    if ~setoff(map(isim,iseries)) % without setoff
                        if any(s(map(isim,iseries)).C0<0) % added 30/11/2015 (deleted layer)
                            screen = dispb(screen,'[%d/%d (%d/%d)]\t%s\t %s (engine=%s with deleted layer(s))...',count,countmax,isim,nsim,currentid,msg,func2str(o.enginedelete));
                            r = o.enginedelete(s(map(isim,iseries))); %senspatankarC(senspatankar_wrapper(s(map(isim,iseries))));
                        else
                            screen = dispb(screen,'[%d/%d (%d/%d)]\t%s\t %s (engine=%s)...',count,countmax,isim,nsim,currentid,msg,func2str(o.enginesingle));
                            r = o.enginesingle(s(map(isim,iseries))); %senspatankar(senspatankar_wrapper(s(map(isim,iseries))));
                        end
                    else % with setoff
                        screen = dispb(screen,'[%d/%d (%d/%d)]\t%s\t %s (engine=%s)...',count,countmax,isim,nsim,currentid,msg,func2str(o.enginesetoff));
                        r = o.enginesetoff(s(map(isim,iseries))); %setoffpatankar(senspatankar_wrapper(s(map(isim,iseries))));
                    end
                else % simulation with a previously calculated profile
                    screen = dispb(screen,'[%d/%d (%d/%d)]\t%s\t %s (engine=%s)...\nreusing ''%s'' located in ''%s''',count,countmax,isim,nsim,currentid,msg,func2str(o.enginerestart),previousid,previousfile);
                    if isempty(data(map(isim,iseries)).parentF)  %added OV 30/08/2017
                        CFrestart = interp1(previousres.r.t*previousres.r.timebase,previousres.r.CF,data(map(isim-1,iseries)).(o.print_t),o.interp1);
                    else
                        CFrestart = s(map(isim,iseries)).CF0;
                    end
                    s(map(isim,iseries)).restart = struct('x',previousres.r.x,... the initial solution is interpolatedd at the previous requested contact time
                       'C',interp1(sqrt(previousres.r.tC*previousres.r.timebase),previousres.r.Cx,sqrt(data(map(isim-1,iseries)).(o.print_t)),o.interp1),...
                       'CF',CFrestart,... added OV 30/08/2017
                       'layerid',previousres.r.layerid,'xlayerid',previousres.r.xlayerid,'C0eq',previousres.r.C0eq,'lengthscale',previousres.r.F.lengthscale);
                    r = o.enginerestart(s(map(isim,iseries))); %senspatankarC(senspatankar_wrapper(s(map(isim,iseries))));
                end
                screen = dispb(screen,'[%d/%d (%d/%d)]\t%s\t... completed in %0.4g s',count,countmax,isim,nsim,currentid,etime(clock,t0));
                alreadydone(map(isim,iseries)) = true;
                
                % Format results
                r.days = r.t * r.timebase / days; % convert result in days for convenience
                
                % Update database
                % Note the subscript as a dot name structure assignment is illegal when the structure is empty.
                fmecadb(1).(currentid) = s(map(isim,iseries));
                fmecadb(1).(currentid).parent = previousid; % parent simulation
                if isfield(data,o.print_inherit)
                    fmecadb(1).(currentid).inherit = data(map(isim,iseries)).(o.print_inherit); % inherited node
                else
                    fmecadb(1).(currentid).inherit = ''; % inherited node
                end
                if isfield(data,o.print_parentF)
                    fmecadb(1).(currentid).parentF = data(map(isim,iseries)).(o.print_parentF); % parent F
                else
                    fmecadb(1).(currentid).parentF = ''; % parent F
                end
                fmecadb(1).(currentid).path = simseries{iseries}(1:isim);
                fmecadb(1).(currentid).isterminal = (isim==nsim); % true if terminal node
                fmecadb(1).(currentid).t = data(map(isim,iseries)).(o.print_t); % requested time
                if isfield(s,'CF0'), fmecadb(1).(currentid).CF0 = s(map(isim,iseries)).CF0; else fmecadb(1).(currentid).CF0 = 0; end
                fmecadb(1).(currentid).CF = interp1(r.t*r.timebase,r.CF,data(map(isim,iseries)).(o.print_t),o.interp1); % CF value
                fmecadb(1).(currentid).CPi = interp1(r.tC*r.timebase,interp1(r.x,r.Cx',0,o.interp1)',data(map(isim,iseries)).(o.print_t),o.interp1);
                fmecadb(1).(currentid).CFi = fmecadb(1).(currentid).CPi * ( r.F.k(1)/r.F.k0 );
                fmecadb(1).(currentid).SML = data(map(isim,iseries)).(o.print_SML);
                % variation in CF value between 2 consecutive steps
                if isempty(previousid)
                    fmecadb(1).(currentid).dCF = fmecadb(1).(currentid).CF;
                else
                    fmecadb(1).(currentid).dCF = fmecadb(1).(currentid).CF - fmecadb(1).(previousid).CF;
                    if isempty(fmecadb(1).(currentid).parentF) && abs(fmecadb(1).(previousid).CF-r.CF(1))>eps
                        if isfield(fmecadb(1).(currentid),'parentF') % likely to be a flow simulation
                            dispb(screen,'\tstationnary condition met between ''%s'' and its ancestor ''%s''',currentid,previousid); screen='';
                        else % chained simulations
                            error('inconsistent result between ''%s'' and its ancestor ''%s''',currentid,previousid);
                        end
                    end
                end
                % concentrations in each layer (added 24/10/11)
                CP = interp1(r.tC*r.timebase,r.Cx,data(map(isim,iseries)).(o.print_t),o.interp1); % interpolated profile for desired time
                lcum = [0 r.F.lrefc];
                for jlayer = 1:length(lcum)-1 %1:nCfield  % before 05/05/2014
                    layerind = find((r.x>=lcum(jlayer)) & (r.x<lcum(jlayer+1)));
                    fmecadb(1).(currentid).(sprintf('CP%d',jlayer)) = trapz(r.x(layerind),CP(layerind)) / ( r.x(layerind(end))-r.x(layerind(1)) );
                end % end (added 24/10/11)
                
                % Save current simulation (savememory implemented on 05/03/2016)
                if o.ramdisk
                    if o.savememory &&  isfield(fmecadb(1).(currentid),o.print_parentF) && ~isempty(fmecadb(1).(currentid).(o.print_parentF))
                        for previousnodeF = fmecadb(1).(currentid).(o.print_parentF);
                            RAMDISK(1).(o.session).(previousnodeF{1}).file = 'cleared to save memory'; % clear parentF node
                            RAMDISK(1).(o.session).(previousnodeF{1}).filename = 'no file';
                            screen = dispb(screen,'FMECAengine:: save ''%s'' results (clear parentF node ''%s'' to save memory) in RAMDISK under session ''%s''',currentid,previousnodeF{1},o.session);
                        end
                        RAMDISK(1).(o.session).(currentid) = struct('file',compressresult(r,data(map(isim,iseries)).(o.print_t)),'filename','compressed data','date',datestr(now));
                    else % no savememory
                        screen = dispb(screen,'FMECAengine:: save ''%s'' results in RAMDISK under session ''%s''',currentid,o.session);
                        RAMDISK(1).(o.session).(currentid) = struct('file',r,'filename',fullfile(o.local,o.outputpath,[currentid '.mat']),'date',datestr(now));
                    end                    
                else % no ramdisk
                    save(fullfile(o.local,o.outputpath,[currentid '.mat']),'r');
                end
                
            else % only reload
                
                screen = dispb(screen,'[%d/%d (%d/%d)]\t%s\t %s... (some files have been removed)',count,countmax,isim,nsim,currentid,msg);
                if o.ramdisk
                    r = RAMDISK.(o.session).(currentid).file;
                    if ischar(r)
                       error('FMECAengine:: node ''%s'' has been cleared from session ''%s'' with message:\n-->\t''%s''',currentid,o.session,r)
                    end
                else
                    load(fullfile(o.local,o.outputpath,[currentid '.mat']))
                end
                
            end % endif action(isim,iseries)<4
            
            % generate some plots as PDF (600 dpi) and PNG (200 dpi)
            % to be modified by end-user to fit needs (current aim is to provide an overall control on simulated conditions)
            % Note that all simulated quantities are stored into a single file and can be reused for any post-treatment
            if ~o.noplot
                requestedtime = data(map(isim,iseries)).(o.print_t);
                Cfatrequestedtime = interp1(r.t*r.timebase,r.CF,requestedtime,o.interp1);
                figure(hfig); clf
                formatfig(hfig,'figname',currentid,'paperposition',[1.8225    3.9453   17.3391   21.7868]);
                hs = subplots(1,[.6 1],0,.1);
                subplot(hs(1))
                if isfield(r.F,'lengthscale'), lengthscale = r.F.lengthscale; else lengthscale = 1; end
                plot(r.x*lengthscale,interp1(r.tC*r.timebase,r.Cx,requestedtime,o.interp1)','-','linewidth',2,'color',rgb('LightCoral'))
                if lengthscale==1, lunit = '-'; else lunit = 'm'; end
                xlabel(sprintf('x (%s)',lunit),'fontsize',14)
                ylabel('C(x) (kg\cdotm^{-3})','fontsize',14)
                title(sprintf('\\bf%s\\rm: Concentration profile in P at t=%0.3g days',currentid,requestedtime/days),'fontsize',14)
                subplot(hs(2)), hold on
                r.CF(abs(r.CF)<realmin) = 0; % remove denormalized numbers (prevent plots)
                plot(r.days,r.CF,'-','linewidth',2,'color',rgb('CornflowerBlue'))
                line(requestedtime/days*[1;1],[0;Cfatrequestedtime],'linestyle',':','linewidth',2,'color',rgb('LightSlateGray'))
                plot(requestedtime/days,Cfatrequestedtime,'bo','markersize',12)
                xlabel('time (days)','fontsize',14)
                ylabel('C_F (kg\cdotm^{-3})','fontsize',14)
                title(sprintf('\\bf%s\\rm: Concentration kinetic in F',currentid),'fontsize',14)
                formatax(hs(1),'fontsize',14)
                formatax(hs(2),'fontsize',14,'xlim',[0 2*requestedtime/days])
                if ~o.noprint
                    dispf('\n >>>> do not move the mouse, the current figure is being printed <<<<')
                    dispf('\tPDF generation'), print_pdf(600,get(gcf,'filename'),fullfile(o.local,o.outputpath),'nocheck')
                    dispf('\tPNG generation'), print_png(200,get(gcf,'filename'),fullfile(o.local,o.outputpath),'',0,0,0)
                    dispf('\tCSV generation'), print_csv(get(gcf,'filename'),fullfile(o.local,o.outputpath))
                    dispf('printing/exportation done.')
                end
            end % noplot
            
        end % if launchsimulation
        
    end % Loop on dependent simulations
    
end %main loop on each series of independent simulations
            
%% Finalizing
% Save the FMECA database
if o.ramdisk
    screen = dispb(screen,'FMECAengine:: save fmecadb in RAMDISK in session ''%s''',o.session);
    RAMDISK(1).(o.session).fmecadb = struct('file',fmecadb,'filename',fullfile(o.local,o.outputpath,o.fmecadbfile),'date',datestr(now));
else
    save(fullfile(o.local,o.outputpath,o.fmecadbfile),'fmecadb')
end
% Reporting
report = sprintf('%d simulations updated/created in %0.4g s',simcount,etime(clock,tstart));
dispb(screen,'\n\t--------------------------------------------------');
dispf('\n\t%s',report);
dispf('\t%d simulations in the current FMECA database',length(fieldnames(fmecadb)))
terminalnodes = find(cellfun(@(node) fmecadb.(node).isterminal,idusercode));
partpaths = cellfun(@(node) fmecadb.(node).path,idusercode,'UniformOutput',false); % all paths
partpathlength = cellfun(@(x) length(x),partpaths);
fullpaths = partpaths(terminalnodes); % all paths (until terminal nodes)
pathlength = partpathlength(terminalnodes);
pathlengthlist = unique(pathlength); npathlength = length(pathlengthlist);
CFvalues = cellfun(@(node) fmecadb.(node).CF,idusercode);
SMLvalues= cellfun(@(node) fmecadb.(node).SML,idusercode);
severity = o.severity(CFvalues,SMLvalues);
CFmax    = max(CFvalues);

if ~o.noplot % ===== BEGIN PLOTS =====
    % Output graph
    hgraph(3) = fmeca2graph('value',CFvalues,...
                          'weight',cellfun(@(node) fmecadb.(node).dCF,{data.(o.print_id)}),...
                          'terminalnodes',terminalnodes); % output graph
    % Final plot (Pareto chart)
    if ~all(isnan(severity)), paretofig = [4 6]; else paretofig=4; end
    vpareto = [CFvalues' severity']; vparetomax = [CFmax 100]; vparetovar = {'C_F' 'Severity'};
    pltcol = ceil(sqrt(npathlength)); pltrow = ceil(npathlength/pltcol);
    for ipareto = 1:length(paretofig)
        hgraph(paretofig(ipareto)) = figure;
        if npathlength==1
            hs = subplots([.4 .6],1,0,0,'alive',2);
        else
            formatfig(hgraph(paretofig(ipareto)),'paperposition',[0.6345    0.6345   19.7150   28.4084])
            hs = subplots(ones(1,pltcol),[3 ones(1,pltrow)],0.05,0.05,'alive',setdiff(1:pltcol*(1+pltrow),(1+pltrow)*(0:pltcol-1)+1));
            hs = reshape(hs,[pltrow pltcol]); hs = hs';
            delete(hs(npathlength+1:end)); hs = hs(1:npathlength);
            hs = [subplots([.4 .6],[3 pltrow],0,0.05*(pltrow+2),'alive',3,'position',gcf);hs(:)];
            for iclasspath=1:npathlength
                classnodes = find(pathlengthlist(iclasspath)==partpathlength); %terminalnodes(pathlengthlist(iclasspath)==pathlength);
                subplot(hs(iclasspath+1))
                ParetoChart(vpareto(classnodes,ipareto),idusercode(classnodes),vparetomax(ipareto),false,vparetovar{ipareto},...
                    sprintf('\\bf%s\\rm of path length \\fontsize{12}\\bf%d',vparetovar{ipareto},pathlengthlist(iclasspath)))
            end
        end
        subplot(hs(1)), ranks=ParetoChart(vpareto(terminalnodes,ipareto),idusercode(terminalnodes),vparetomax(ipareto),true,vparetovar{ipareto});
        formatax(hs(1),'fontsize',14)
        formatax(hs(2:end),'fontsize',10,'xticklabelmode','auto')
    end

    % Concentration kinetics (if requested)
    ranks = flipud(ranks(:));
    [x,y] = KineticsAssembling(fullpaths); % be patient
    hgraph(5) = figure;
    hs = subplots([.7 .3],1,.05);
    plotpubcolor = interp1(linspace(0,1,ncol),jet(ncol),CFvalues(terminalnodes(ranks))/CFmax);
    if any(isnan(plotpubcolor(:))), plotpubcolor = [0 0 0]; end
    subplot(hs(1))
    hp = plotpub(x(ranks),y(ranks),'linestyle','-','linewidth',1,'marker','none','color',plotpubcolor);
    xlabel('time (days)','fontsize',14)
    ylabel('C_F','fontsize',14)
    formatax(hs(1),'fontsize',12)
    title(strrep(sprintf('%s[\\bf%s\\rm]',o.fmecamainfile,o.fmecasheetname),'_','\_'),'fontsize',12)
    legendpub(hp,regexprep(idusercode(terminalnodes(ranks)),'_','\\_'),hs(2),[],'fontsize',10);
end % ===== END PLOTS =====

% final HTML document
doc=fmeca2html('graph2345',true,'ahref',inputhtml);
outdocurl = sprintf('file:///%s/%s',regexprep(fullfile(o.local,o.outputpath),'\\','/'),doc);
indocurl  = sprintf('file:///%s/%s',regexprep(fullfile(o.local,o.outputpath),'\\','/'),inputhtml);

% display link
dispf('\n\t>> Direct links to follow <a href="%s" title="input HTML">the input HTML table</a> and <a href="%s" title="output HTML">the output HTML table</a>',...
    indocurl,outdocurl)

%% additional outputs
if o.mergeoutput, fmecadb = fmecamerge(fullfile(o.local,o.outputpath,o.fmecadbfile)); end
if o.cls, disp('Clear all figures');
    delete(findobj(allchild(0),'-regexp','Name','^Biograph'))
    delete(hgraph(ishandle(hgraph)));
end
if nargout>1, dataout = data; end
if nargout>2, options = o; end

%===============================================================================================================
%% NESTED FUNCTIONS (share the same workspace as fmecaengine)
%===============================================================================================================
    %%%% --------------------------------------------------------------------------------------    
    % Inheritance strategy (see also: PropagateInheritance())
    % This strategy must be forced each time PropagateScale() is called
    % Note that additional inheritance is propagated with parent during simulation
    % If forced (then new roots are created), all modes of inheritance must be considered.
    %%%% --------------------------------------------------------------------------------------
    function ApplyInheritanceStrategy(forced)
        if forced % propagate first along the tree provided by user and long the new tree
            % FIRST STEP: inheritance propagated the sole original nodes
            PropagateInheritance('inherit','descend',1:ndata0); % higher precedence
            PropagateInheritance('parent','descend',1:ndata0);
            % SECOND STEP: inheritance propagted to the remainder nodes
            if length(data)>ndata0
                PropagateInheritance('inherit','descend'); % higher precedence
                PropagateInheritance('parent','descend');
            end
        else
            PropagateInheritance('inherit','descend'); % build all possible paths for inheritance (start with largest ones, likely to include root)
        end
    end

    %%%% --------------------------------------------------------------------------------------
    % Propagate inheritance (protect parent, nfo, Foscale, Kscale)
    % dependence = 'inherit' or 'parent'
    % mode = 'ascend' or 'descend'
    % ind = indices to propagate inheritance
	%%%% --------------------------------------------------------------------------------------
    function PropagateInheritance(dependence,mode,ind)
        %properties not to be modified by PropagateInheritance()
        protectedproperties = intersect(fieldnames(data)',{o.print_parent 'nfo' 'Foscale' 'Kscale'});
        cache = cell2struct(repmat({[]},1,length(protectedproperties)),protectedproperties,2);
        if nargin<3, ind = []; end
        if isempty(ind), ind = 1:length(data); end
        switch dependence
            case 'inherit'
                if isfield(data,o.print_inherit)
                    [depseries,~,depmap] = buildmarkov({data(ind).(o.print_id)},{data(ind).(o.print_inherit)},'sort',mode);
                else
                    return
                end
            case 'parent'
                [depseries,~,depmap] = buildmarkov({data(ind).(o.print_id)},{data(ind).(o.print_parent)},'sort',mode);
        end
        depmap(depmap>0) = ind(depmap(depmap>0)); % index conversion based on ind
        for idepseries=1:length(depseries)
            for idepsim=2:length(depseries{idepseries})
                for pp=protectedproperties, cache.(pp{1}) = data(depmap(idepsim,idepseries)).(pp{1}); end
                data(depmap(idepsim,idepseries)) = argcheck(data(depmap(idepsim,idepseries)),data(depmap(idepsim-1,idepseries)),'','NaNequalmissing','case');
                for pp=protectedproperties, data(depmap(idepsim,idepseries)).(pp{1})=cache.(pp{1}); end
            end
        end
    end

    %%%% --------------------------------------------------------------------------------------
    % Propagate recursively multiple scaling (param2scale='Foscale' or 'Kscale')
    % return true if newroots have been created
	%%%% --------------------------------------------------------------------------------------
    function newroots = PropagateScale(param2scale)
        newroots = false;
        % scaling values
        scalelist = {data.(param2scale)};
        isscale = cellfun(@(x) ~isnan(x(1)),scalelist);
        if ~any(isscale) % update id, parent, inherit
            ndata = length(data);
            idusercode = {data.(o.print_id)};
            parent = {data.(o.print_parent)};
            if isfield(data,'inherit'), inherit = {data.(o.print_inherit)}; end
            return
        end
        % add fields (if missing)
        if ~isfield(data,'inherit'), f=fieldnames(data); [data.(o.print_inherit)] = deal(''); data = orderfields(data,[{o.print_inherit};f]); end % add field nfo
        if ~isfield(data,'nfo'), f=fieldnames(data); [data.nfo] = deal(''); data = orderfields(data,[{'nfo'};f]); end % add field nfo
        % pick one node to repeat and process
        first = find(isscale,1,'first'); % first id with multi-level scaling
        [~,~,t] = buildmarkov({data.idusercode},{data.(o.print_parent)},'sort','desc'); % build children table
        [allchildren,finalallpaths] = findgrandchildren(first,t);
        nodestoduplicate = [first;allchildren]; % selected node and its children
        nnodestoduplicate = length(nodestoduplicate);
        scale = scalelist{first}; % read scale
        iscolumnvecctor = (size(scale,1)>size(scale,2)); % true if scale is a column vector
        scale = setdiff(scale,1); % remove one and duplicated values, all values are ordered
        nscale = numel(scale);
        % update original
        if isfield(data,[param2scale 'copy']), nfoscale = data(first).([param2scale 'copy']);
        else nfoscale = vec2str(data(first).(param2scale));
        end
        if isempty(data(first).nfo)
            data(first).nfo = sprintf('%s.%s=%s',data(first).(o.print_id),param2scale,nfoscale);
        else
            data(first).nfo = sprintf('%s, %s.%s=%s',data(first).nfo,data(first).(o.print_id),param2scale,nfoscale);
        end
        data(first).(param2scale) = NaN;
        % copy, rename copies and inherit values from original ones
        copy = repmat(data(nodestoduplicate),1,nscale); % creates copies (including children)
        [ii,jj] = ndgrid(1:nnodestoduplicate,1:nscale);
        newid = cellfun( @(name,i,j) sprintf([name extension.(param2scale)],i,j),{copy.(o.print_id)}',num2cell(ii(:),2),num2cell(jj(:),2),'UniformOutput',false);
        for newiddup=findduplicates([newid;idusercode'])'; % for all duplicated names (due to succesive calls of FMECAENGINE)
            inewidudp = find(ismember(newid,newiddup)); icopyversn = 0; badid = newid{inewidudp};
            dispf('WARNING:: FMECAENGINE detected that the automatic name ''%s'' interacts with user nomenclature (or with previous FMECAENGINE instances)',badid)
            while ismember(newid(inewidudp),idusercode) % while name exist
                icopyversn = icopyversn+1; newid{inewidudp} = sprintf(extension.ALT,badid,icopyversn);
            end
        end
        [copy.(o.print_id)] = deal(newid{:}); % update id
        [copy.(o.print_inherit)] = deal(data(repmat(nodestoduplicate,1,nscale)).(o.print_id)); % inherit from original
        % update dependence between copied children (a tree dependence is assumed)
        for ipath=1:length(finalallpaths) % descending all possible paths
            for child=2:length(finalallpaths{ipath})
                [copy(finalallpaths{ipath}(child),:).(o.print_parent)] = deal(copy(finalallpaths{ipath}(child-1),:).(o.print_id));
            end
        end
        % update scaling
        fall = fieldnames(copy)';
        propreg = o.(prop2scale.(param2scale));
        if iscolumnvecctor, iistop = nnodestoduplicate; else iistop = 1; end
        validcopy = true(nnodestoduplicate,nscale);
        for ii=1:nnodestoduplicate
            for jj=1:nscale
                if ii<=iistop
                    % if isempty(copy(ii,jj).nfo) % remove restriction 9/5/11 
                    copy(ii,jj).nfo = sprintf('%s.%s=%0.5g',data(first).(o.print_id),param2scale,scale(jj));
                    % end % remove restriction 9/5/11 
                    for prop = fall(~cellfun('isempty',regexp(fall,propreg)))
                        valuetoscale = copy(ii,jj).(prop{1});
                        if isnan(valuetoscale) % inheritance is required (via parent)
                            [ilevel,ipath] = ind2sub(size(t),find(t==first));
                            ntstpaths = length(ipath); itstpath = 1;
                            while isnan(valuetoscale) && itstpath<=ntstpaths % test all paths
                                valuesingenealogy = cat(1,data(t(1:ilevel(itstpath)-1,ipath(itstpath))).(prop{1}));
                                valuetoscale = valuesingenealogy(find(~isnan(valuesingenealogy),1,'last'));
                                if isempty(valuetoscale), valuetoscale=NaN; end
                                itstpath = itstpath+1;
                            end
                            if isnan(valuetoscale)
                                dispf('WARNING: Unable to find a valid value for the property ''%s'' of the new node ''%s''. Check your input table.',prop{1},copy(ii,jj).(o.print_id))
                            end
                        end
                        if scale(jj) == 0; % special case (node to be removed)
                            validcopy(ii,jj)=false; 
                            scale(jj) = 1; % do not propagate scale == 0
                        end
                        copy(ii,jj).(prop{1}) = valuetoscale * scale(jj);
                    end
                else
                    if isempty(copy(ii,jj).nfo)
                        copy(ii,jj).nfo = sprintf('%s.%s=1',data(first).(o.print_id),param2scale);
                    end
                end % endif ii<=iistop
                % reparenting orphan nodes
                if ~validcopy(ii,jj)
                    for ipath=1:length(finalallpaths) % descending all possible paths
                        ideadnode = find(finalallpaths{ipath}==ii);
                        if ideadnode<length(finalallpaths{ipath})
                            copy(finalallpaths{ipath}(ideadnode+1),jj).(o.print_parent) = copy(ii,jj).(o.print_parent); % update parent
                        end
                        if isempty(copy(ii,jj).(o.print_parent))
                            copy(ii+1,jj).nfo = sprintf('new root<br />parent %s removed',copy(ii,jj).(o.print_id)); newroots = true;
                        else copy(ii+1,jj).nfo = sprintf('new branching:<br />parent %s removed',copy(ii,jj).(o.print_id));
                        end
                    end % for ipath
                end %if ~validcopy(ii,jj)
            end %for jj=1:nscale
        end % for ii=1:nodestoduplicate
        % addd copy to data
        copy = copy(validcopy);
        data = [data;copy(:)];
        newroots = newroots | PropagateScale(param2scale); % propagate next
        
    end %end PropagateScale

    %%%% --------------------------------------------------------------------------------------
    %%%% Find all nth order children of parent p from a numerical tree (coded as buildmarkov does)
    %%%% syntax [grandchildren,finalallpaths] = findgrandchildren(p,treenum)
    %%%% grandchildren = all dependent children nodes (at any depth)
    %%%% finalallpaths = all paths (including p) to reach grandchildren
    %%%% Note they are reindexed 1:length(grandchildren)+1 with 1 as p to be reused in subtree copies
    %%%% --------------------------------------------------------------------------------------
    function [grandchildren,finalallpaths] = findgrandchildren(p,treenum)
        npaths = size(treenum,2);
        found = cell(npaths,1);
        for ii=1:npaths
            ip = find(treenum(:,ii)==p,1,'first');
            depthmax = find(treenum(:,ii)>0,1,'last');
            if any(ip) && ip<depthmax
                found{ii} = treenum(ip+1:depthmax,ii);
            end
        end
        found = found(~cellfun('isempty',found)); npaths = length(found);
        grandchildren = unique(cat(1,found{:})); %unique([found{:}]);
        if nargout>1 % reindex all possible subpaths starting from p (added 11/05/11)
            originalcodes = [p;grandchildren];
            finalcodes(originalcodes) = 1:length(originalcodes);
            [originalallpaths,finalallpaths] = deal(cell(npaths,1));
            for ii=1:npaths
                originalallpaths{ii} = [p;found{ii}];
                finalallpaths{ii} = finalcodes(originalallpaths{ii});
            end
        end
    end

    %%%% --------------------------------------------------------------------------------------
    %%%% Generate HTML file (mimic initial ODS file)
    %%%% syntax: fmeca2html('filenamemodifyer','extension to add','links',true/false,'graph',true/false,'graph2',true/false,)
    %%%% --------------------------------------------------------------------------------------
    function doc=fmeca2html(varargin)
        % returns rapidly if nothml is used
        if o.nohtml, if nargout, doc = '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN"><html>nohtml option used</html>'; end, return, end
        % argcheck
        htmlopt = argcheck(varargin,struct('filenamemodifyer','','links',true,'graph',true,'graph2345',false,'atext','input','ahref','','atarget','input'),[],[],'case');
        separator = '&nbsp;&nbsp;&raquo;&nbsp;';
        % generate graph images
        if htmlopt.graph
            if ~isempty(htmlopt.ahref), htmllink = sprintf('<a href="%s" title="open %s" target="%s">%s</a>',htmlopt.ahref,htmlopt.atext,htmlopt.atarget,htmlopt.atext);
            else
                htmllink = sprintf('<a href="%s" title="go to results">result page</a>',regexprep(o.fmecamainfile,'\.ods$','.html'));
            end
            graphlinks = {sprintf('\n<br />%s',htmllink);''}; %... input link
            screen = ''; tprint = clock;
            if ishandle(hgraph(1))
                graphfilePNG = regexprep(o.fmecamainfile,'\.ods$',sprintf('%s.graph.png',htmlopt.filenamemodifyer));
                graphfilePDF = regexprep(o.fmecamainfile,'\.ods$',sprintf('%s.graph.pdf',htmlopt.filenamemodifyer));
                if ~o.noprint
                    screen = dispb(screen,'\tprinting the dependence graph...');
                    figure(hgraph(1)); print_pdf(300,graphfilePDF,fullfile(o.local,o.outputpath),'nocheck')
                    figure(hgraph(1)); print_png(200,graphfilePNG,fullfile(o.local,o.outputpath),'',0,0,0); close(hgraph(1))%truncateim(fullfile(o.local,o.outputpath,graphfilePNG))
                end
                graphlinks{3} = sprintf( ...
                    ['%s<a href="%s" title="open depedence graph as an image" target="dependence">dependence graph</a>&nbsp;',... PNG dependence
                    '(<a href="%s" title="open dependence graph as a pdf" target="dependence">pdf</a>)'],... PDF dependence
                    separator,graphfilePNG,graphfilePDF);
            end
            if htmlopt.graph2345
                if ishandle(hgraph(2))
                    graphfile2PNG = regexprep(o.fmecamainfile,'\.ods$',sprintf('%s.inherit.png',htmlopt.filenamemodifyer));
                    graphfile2PDF = regexprep(o.fmecamainfile,'\.ods$',sprintf('%s.inherit.pdf',htmlopt.filenamemodifyer));
                    if ~o.noprint
                        screen = dispb(screen,'\tprinting the inheritance graph...');
                        figure(hgraph(2)); print_pdf(300,graphfile2PDF,fullfile(o.local,o.outputpath),'nocheck')
                        figure(hgraph(2)); print_png(200,graphfile2PNG,fullfile(o.local,o.outputpath),'',0,0,0); close(hgraph(2)); %truncateim(fullfile(o.local,o.outputpath,graphfile2PNG))
                    end
                    graphlinks{2} = sprintf( ...
                        ['%s<a href="%s" title="open inheritance graph as an image" target="inheritance">inheritance graph</a> ',... PNG inheritance
                        '(<a href="%s" title="open inheritance graph as a pdf" target="inheritance">pdf</a>)'], ... PDF inheritance
                        separator,graphfile2PNG,graphfile2PDF);
                end
                if ishandle(hgraph(3))
                    graphfile3PNG = regexprep(o.fmecamainfile,'\.ods$',sprintf('%s.result.png',htmlopt.filenamemodifyer));
                    graphfile3PDF = regexprep(o.fmecamainfile,'\.ods$',sprintf('%s.result.pdf',htmlopt.filenamemodifyer));
                    if ~o.noprint
                        screen = dispb(screen,'\tprinting the mass transfer graph...');
                        figure(hgraph(3)); print_pdf(300,graphfile3PDF,fullfile(o.local,o.outputpath),'nocheck')
                        figure(hgraph(3)); print_png(200,graphfile3PNG,fullfile(o.local,o.outputpath),'',0,0,0); close(hgraph(3)); %truncateim(fullfile(o.local,o.outputpath,graphfile3PNG))
                    end
                    graphlinks{end+1} = sprintf( ...
                        ['%s<a href="%s" title="open result graph as an image" target="result">result graph</a>&nbsp;',... PNG dependence
                        '(<a href="%s" title="open result graph as a pdf" target="result">pdf</a>)'],... PDF dependence
                        separator,graphfile3PNG,graphfile3PDF);
                end
                if ishandle(hgraph(4))
                    graphfile4PNG = regexprep(o.fmecamainfile,'\.ods$',sprintf('%s.pareto.png',htmlopt.filenamemodifyer));
                    graphfile4PDF = regexprep(o.fmecamainfile,'\.ods$',sprintf('%s.pareto.pdf',htmlopt.filenamemodifyer));
                    if ~o.noprint
                        screen = dispb(screen,'\t printing the Pareto chart (concentrations)...');
                        figure(hgraph(4)); print_pdf(300,graphfile4PDF,fullfile(o.local,o.outputpath),'nocheck')
                        figure(hgraph(4)); print_png(200,graphfile4PNG,fullfile(o.local,o.outputpath),'',0,0,0); %truncateim(fullfile(o.local,o.outputpath,graphfile4PNG),false)
                    end
                    graphlinks{end+1}  = sprintf( ...
                        ['%s<a href="%s" title="open the concentration Pareto chart as an image" target="pareto">Pareto chart</a>&nbsp;',... PNG chart
                        '(<a href="%s" title="open the concentration Pareto chart as a pdf" target="pareto">pdf</a>)'],... PDF chart
                        separator,graphfile4PNG,graphfile4PDF);
                end
                if ishandle(hgraph(5))
                    graphfile5PNG = regexprep(o.fmecamainfile,'\.ods$',sprintf('%s.kinetics.png',htmlopt.filenamemodifyer));
                    graphfile5PDF = regexprep(o.fmecamainfile,'\.ods$',sprintf('%s.kinetics.pdf',htmlopt.filenamemodifyer));
                    if ~o.noprint
                        screen = dispb(screen,'\tprinting the concentration kinetics plots...');
                        figure(hgraph(5)); print_pdf(300,graphfile5PDF,fullfile(o.local,o.outputpath),'nocheck')
                        figure(hgraph(5)); print_png(200,graphfile5PNG,fullfile(o.local,o.outputpath),'',0,0,0); %truncateim(fullfile(o.local,o.outputpath,graphfile5PNG),false)
                        figure(hgraph(5)); print_csv(graphfile5PNG,fullfile(o.local,o.outputpath)) %  note that the initial extension is removed with print_csv, which appends automatically '.csv')
                    end
                    graphlinks{end+1}  = sprintf( ...
                        ['%s<a href="%s" title="open kinetics as an image" target="kinetics">Kinetics</a>&nbsp;',... PNG chart
                        '(<a href="%s" title="open kinetics as a pdf" target="kinetics">pdf</a>)'],... PDF chart
                        separator,graphfile5PNG,graphfile5PDF);
                end
                if ishandle(hgraph(6))
                    graphfile6PNG = regexprep(o.fmecamainfile,'\.ods$',sprintf('%s.severity.png',htmlopt.filenamemodifyer));
                    graphfile6PDF = regexprep(o.fmecamainfile,'\.ods$',sprintf('%s.severity.pdf',htmlopt.filenamemodifyer));
                    if ~o.noprint
                        screen = dispb(screen,'\t printing the Pareto chart (severity)...');
                        figure(hgraph(6)); print_pdf(300,graphfile6PDF,fullfile(o.local,o.outputpath),'nocheck')
                        figure(hgraph(6)); print_png(200,graphfile6PNG,fullfile(o.local,o.outputpath),'',0,0,0); %truncateim(fullfile(o.local,o.outputpath,graphfile6PNG),false)
                    end
                    graphlinks{end+1}  = sprintf( ...
                        ['%s<a href="%s" title="open the severity Pareto chart as an image" target="pareto">Severity chart</a>&nbsp;',... PNG chart
                        '(<a href="%s" title="open the severity Pareto chart as a pdf" target="pareto">pdf</a>)'],... PDF chart
                        separator,graphfile6PNG,graphfile6PDF);
                end %if ishandle(hgraph(6))
            end % if htmplot.graph2345
            if o.noplot
                screen = dispb(screen,'\tno graph and figure have been generated');
            else
                screen = dispb(screen,'\tall graphs and figures printed in %0.3g s',etime(clock,tprint));
            end
            graphlinks = sprintf('%s\n',graphlinks{:});
        else graphlinks = '';
        end
        % generate the HTML code
        htmlfile = regexprep(o.fmecamainfile,'\.ods$',sprintf('%s.html',htmlopt.filenamemodifyer));
        %[~,~,exthtml]=fileparts(htmlfile); if isempty(exthtml), htmlfile=sprintf('%s.html',htmlfile); end % added 08/05/14 (removed 09/05/14)
        % header including CSS
        %       CSS body modified from: http://www.code-sucks.com/css%20layouts/fixed-width-css-layouts/
        %       CSS table modified from: http://icant.co.uk/csstablegallery/tables/99.php
        html = {
            '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">'
            '<html>'
            sprintf('<!-- %s: %s on %s',datestr(now),mfilename,localname)
            sprintf('     INRA\\Olivier Vitrac -->\n')
            '    <head>'
            '        <meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1">'
            '        <link rel="shortcut icon" href="./table.png" type="image/x-icon">'
            sprintf(...
            '        <title>%s</title>',o.fmecamainfile)
            '        <style type="text/css">'
            '        <!--'
            '        body {font-family: Arial, Helvetica, sans-serif; font-size: 12px; }'
            '        #wrapper {margin: 0 auto; }'
            '        #leftheader { color: #333; border: 1px solid #ccc; background: #BD9C8C; margin: 0px 5px 5px 0px; padding: 10px; height: 100px; width: 300px; float: left; }'
            '        #header { color: #333; padding: 10px; border: 1px solid #ccc; height: 100px;  width: 500px;  margin: 0px 5px 5px 0px; background: #E7DBD5;'
            '                  font:normal 20px georgia,garamond,serif; float: right; display: inline; font-weight:bold; text-transform:uppercase; letter-spacing:4px; text-align:right; }'
            '        #nfo { color: #333; padding: 10px; border: 1px solid #ccc; margin: 0px 0px 5px 0px; background: #DAC8BF; clear:both;}'
            '        #content { color: #333; border: 1px solid #ccc; background: #F2F2E6; margin: 0px 0px 5px 0px; padding: 10px; }'
            '        table { background:#D3E4E5; border:1px solid gray; border-collapse:collapse; color:#fff; font:normal 12px verdana, arial, helvetica, sans-serif; margin-left: auto; margin-right: auto; }'
            '        caption { border:1px solid #5C443A; color:#5C443A; font-weight:bold; letter-spacing:2px; padding:6px 4px 8px 0px; text-align:center; text-transform:uppercase; }'
            '        td, th { color:#363636; padding:.4em; }'
            '        tr { border:1px dotted gray; }'
            '        thead th, tfoot th { background:#5C443A; color:#FFFFFF; padding:3px 10px 3px 10px; text-align:center; }'
            '        tbody td a { color:#363636; text-decoration:none; }'
            '        tbody td a:visited { color:gray; text-decoration:line-through; }'
            '        tbody td a:hover { text-decoration:underline; }'
            '        tbody th a { color:#363636; font-weight:normal; text-decoration:none; }'
            '        tbody th a:hover { color:#363636; }'
            '        tbody td+td+td+td a { background-position:left center; background-repeat:no-repeat; color:#03476F; padding-left:15px; }'
            '        tbody td+td+td+td a:visited { background-position:left center; background-repeat:no-repeat; }'
            '        tbody th, tbody td { vertical-align:top; }'
            '        tfoot td { background:#5C443A;color:#FFFFFF; padding-top:3px; }'
            '        .odd { background:#fff; }'
            '        .txtnoherit { font-weight:bold; text-align:left; }'
            '        .numnoherit { font-style:normal; text-align:right; }'
            '        .numinherit { font-style:italic; text-decoration:line-through; text-align:right}'
            '        tbody tr:hover { background:#99BCBF; border:1px solid #03476F; color:#000000; }'
            '        -->'
            '       </style>'
            '    </head>'
            '    <body><div id="wrapper">'
            '        <div id="leftheader">'
            '           <a href="http://modmol.agroparistech.fr/SFPD/"><img src="http://modmol.agroparistech.fr/SFPD/css/SFPD_txtsmall.png" alt="SafeFoodPack Design"></a>'
            '        </div>'
            '        <div id="header">'
            '         Failure mode,<br />effects,<br/> and criticality analysis<br/>(FMECA)'
            '        </div>'
            sprintf(...
            '        <div id="nfo">Engine="<b>%s</b>" (version <b>%0.3g</b>)&nbsp;&nbsp;&nbsp;&nbsp;Host="<b>%s</b>@<b>%s</b>" (mlm release <b>%s</b>)&nbsp;&nbsp;&nbsp;&nbsp;Local Path="<b>%s</b>"<br />',...
            mfilename,versn,username,localname,regexprep(mlmver.Release,'\(|\)',''),o.local)
            sprintf(...
            '        Worksheet="<b>%s</b>"&nbsp;&nbsp;&nbsp;&nbsp;Input File="<b>%s</b>"&nbsp;&nbsp;&nbsp;&nbsp;FMECA Database="<b>%s</b>"&nbsp;&nbsp;&nbsp;&nbsp;Input Folder="<b>%s</b>"&nbsp;&nbsp;&nbsp;&nbsp;Output Folder="<b>%s</b>"%s</div>',...
            o.fmecasheetname,o.fmecamainfile,o.fmecadbfile,o.inputpath,o.outputpath,graphlinks)
            '        <div id="content"><p><hr /></p>'
            '        <table>'
            };
        % protect data (version 0.6 and later)
        data = protectcell(data); % all cells are temporarily converted into char
        % check columns
        f=fieldnames(data); nf = length(f);
        isvalid = cellfun(@(f) any(cellfun(@(x) ~isempty(x) && ~any(isnan(x)),{data.(f)})),f); % valid fields (not full empty or NaN cells)
        isnum   = isvalid & cellfun(@(f) all(cellfun(@(x) isnumeric(x),{data.(f)})),f); % valid numeric fields
        % table headers
        if length(find(isvalid))>15,  modifyer = {'' ''};
        else                          modifyer = {'</tr>' '<tr>'};
        end
        if htmlopt.links
            CONCcol = [sprintf('<th>CF</th>\n') sprintf('<th>CP%d</th>\n',1:nCfield)]; % concentration columns (added 24/10/11)
            MATcol = sprintf('<th>PDF output</th>\n<th>PNG output</th>\n<th>MAT date</th>\n<th>MAT size</th>\n%s</tr>\n',CONCcol);
            nfodb=fileinfo(fullfile(o.local,o.outputpath,o.fmecadbfile),'',[],[],o.ramdisk); % forces noerror if ramdisk used
            tablefooter = {
                sprintf('\n<tfoot><tr><th scope="row">FMECA database</th><td colspan="4">%d simulations</td><td colspan="4">%s</td><th scope="row">last update</th><td colspan="4">%s</td>%s',...
                ndata,o.fmecadbfile,nfodb.date,modifyer{1})
                sprintf('%s<th scope="row">last report</th><td colspan="4">%s</td></tr></tfoot>\n',modifyer{2},report)
            };
        else
            MATcol=sprintf('</tr>\n'); % before 24/10/11 ''
            tablefooter = {
                sprintf('\n<tfoot><tr><th scope="row">INPUT TABLE</th><td colspan="4">%d simulation definitions</td>',ndata)
                sprintf('<th scope="row">date</th><td colspan="4">%s</td></tr></tfoot>\n',datestr(now))
                };
        end
        headers = sprintf('<tr>%s%s',sprintf('<th>%s</th>\n',f{isvalid}),MATcol);
        table = cell(ndata+5,1);
        table(1) = {sprintf('\n<caption>%s</caption>\n',regexprep(strtrim(nfodata),'\s{2,}','&nbsp;|&nbsp;'))};
        table(2:8) = {
            sprintf('\n<thead>\n')
            regexprep(headers,{'usercode|nounit|kgm3|m2s|m|(?<=t)s|\s+output|date|size' '(D|l|(KFP)|(CP))([1-9])' '(l)(F)' '(0)'},...
            {'' '$1<sub>$2</sub>' '$1<sub>$2</sub>' '<sup>$1</sup>'})
            regexprep(headers,{'<th>(.*?)</th>','(PDF\s+)|(PNG\s+)|id|parent|SML|t(?=s)|lF+|l\d+|(CP\d+)|(KFP\d+)|D\d+|Bi|MAT' 'm2s' 'kgm3kgm3' 'kgm3' '(\d)' 'nounit'},...
            {'<th><small><i>$1</i></small></th>' '' 'm2/s' '(kg/m3)/(kg/m3)' 'kg/m3' '<sup>$1</sup>' 'no unit'})
            '</thead>'
            tablefooter{1}
            tablefooter{2}
            sprintf('\n<tbody>\n')
            }; % 1st row = variable, 2nd row = unit
        % table body
        if htmlopt.links
            CONCcol = ['<td>%0.6g</td>\n' repmat('<td>%0.6g</td>\n',1,nCfield)]; % concentration columns (added 24/10/11)
            MATcol = [repmat('<td align="center">%s</td>\n',1,2) repmat('<td align="center"><small>%s</small></td>\n',1,2) CONCcol];
        else
            MATcol='';
        end
        tr = {['<tr>%s'             MATcol '</tr>\n']
              ['<tr class="odd">%s' MATcol '</tr>\n']};
        tdformat = {'<td class="%s">%s</td>\n' '<td class="%s">%g</td>\n'};  td = [tdformat{isnum(isvalid)+1}];
        tdclass = {'txtnoherit' 'numnoherit' 'numinherit'};
        pdflink = '<a href="%s.pdf" title="open simulation results as a PDF document">document</a>';
        pnglink = '<a href="%s.png" title="open simulation results as a PNG image">image</a>';
        for i=1:ndata
            tmp = struct2cell(data(i));
            isinherit = false(nf,1);
            if any(data(i).(o.print_parent))
                iparent = ismember(idusercode,data(i).(o.print_parent));
                tmp2 = struct2cell(data(iparent));
                isinherit(isnum) = isinherit(isnum) | cellfun(@(a,b) matcmp(a,b),tmp(isnum),tmp2(isnum)); %fixed on 08/05/2014 (for vectors)([tmp{isnum}]==[tmp2{isnum}])';
            end
            if isfield(data,'inherit') && any(data(i).inherit)
                iparent = ismember(idusercode,data(i).inherit);
                tmp2 = struct2cell(data(iparent));
                isinherit(isnum) = isinherit(isnum) | cellfun(@(a,b) matcmp(a,b),tmp(isnum),tmp2(isnum)); %fixed on 08/05/2014  ([tmp{isnum}]==[tmp2{isnum}])';
            end
            tmp = tmp(isvalid)'; [tmp{cellfun(@(x)any(isnan(x)),tmp)}] = deal('');
            % fix maximum width of columns (added 08/05/11)
            toolong = cellfun(@(x) ischar(x) && (length(x)>o.maxwidth),tmp);
            tmp(toolong) = wraptext(tmp(toolong),o.maxwidth,'<br />',8); % change tolerance=8 if required
            % add class
            tmp=[tdclass(isnum(isvalid)+1+isinherit(isvalid));tmp]; %#ok<AGROW>
            if htmlopt.links
                [~,nfomat] = fileinfo(fullfile(o.local,o.outputpath,[data(i).(o.print_id) '.mat']),'',false,[],o.ramdisk); %force noerror if ramdisk used
                nfomat=regexp(nfomat,'\s{2,}','split');
                if datenum(nfomat{2})<today, nfomat{2} = char(regexp(nfomat{2},'^[^\s]+','match')); end % remove timestamp if file older than 1 day
                validlayers = 1:nCfield;
                validCPfield = arrayfun(@(jlayer) isfield(fmecadb.(data(i).(o.print_id)),sprintf('CP%d',jlayer)),validlayers);
                validlayers = validlayers(validCPfield);
                table{i+8} = sprintf(tr{mod(i,2)+1},sprintf(td,tmp{:}),... fixed 8 instead 9 (24/10/11)
                    sprintf(pdflink,data(i).(o.print_id)),...
                    sprintf(pnglink,data(i).(o.print_id)),...
                    nfomat{2},nfomat{3}, ...
                    cellfun(@(f) fmecadb.(data(i).(o.print_id)).(f),[{'CF'} arrayfun(@(jlayer) sprintf('CP%d',jlayer),validlayers,'UniformOutput',false)]) ...
                    );
            else
                table{i+8} = sprintf(tr{mod(i,2)+1},sprintf(td,tmp{:}));
            end
        end
        htmlbottom = {
            sprintf('\n</tbody>\n')
            '        </table>'
            '       </div>'
            sprintf(...
            '      <p /><hr /><p align="center">&mdash;&nbsp;%s&nbsp;&mdash;<br />&copy;<a href="http://www.inra.fr">INRA</a>/<a href="mailto:olivier.vitrac@agroparistech.fr">Olivier Vitrac</a></p>',datestr(now))
            '</div></body>'
            '</html>'
            };
        % unprotect data (version 0.6 and later)
        data = unprotectcell(data); % recreate cells when needed
        % write HTML file
        fid = fopen(fullfile(o.local,o.outputpath,htmlfile),'w');
        fprintf(fid,'%s\n',html{:},table{:},htmlbottom{:});
        if fclose(fid), error('unable to create the HTML output file ''htmlfile'' in ''%s''',htmlfile,fullfile(o.local,o.outputpath)); end
        % add icon
        if exist(fullfile(iconpath,iconfile),'file')
            copyfile(fullfile(iconpath,iconfile),fullfile(o.local,o.outputpath,iconfile));
        else
            dispf('WARNING: unable to find the icon file ''%s''\nExpected directory ''%s''\nCorrupted installation?',iconfile,iconpath)
        end
        if nargout, doc = htmlfile; end
        
    end % end fmeca2html -------------------------------------------

    %%%% --------------------------------------------------------------------------------------
    %%%% Generate GRAPH (requires the Bioinformatics Toolbox)
    %%%% properties: ref, prop, color, colorref, textcolor, value, weight, terminalnodes
    %%%% --------------------------------------------------------------------------------------
    function hgraphtmp = fmeca2graph(varargin)
        if o.nograph || ~bioinfo_is_installed, hgraphtmp=NaN; return, end
        ndata = length(data);
        paperprop = {'PaperUnits','Centimeters','PaperType','A0','PaperOrientation','Landscape'};
        graphopt = argcheck(varargin,struct('ref',[],'prop',o.print_parent,'color',[],'colorref',rgb('PeachPuff'),'textcolor',[],'value',[],'weight',[],'terminalnodes',[]));
        if isempty(graphopt.weight), w = ones(1,ndata); else w = graphopt.weight(:)'; w(w==0)=NaN; end
        if ~isfield(data,graphopt.prop), hgraphtmp=NaN; return, end
        [~,~,~,c] = buildmarkov({data.(o.print_id)},{data.(graphopt.prop)});
        nterminalnodestoadd = length(graphopt.terminalnodes);
        g = sparse(ndata+nterminalnodestoadd,ndata+nterminalnodestoadd);
        if nterminalnodestoadd % with terminal nodes
            for i=1:ndata, j=c(:,i)>0; g(i,c(j,i))=w(i); end %#ok<SPRIX>
            for i=1:nterminalnodestoadd, g(graphopt.terminalnodes(i),ndata+i) = w(graphopt.terminalnodes(i)); end %#ok<SPRIX>
            if ~isempty(graphopt.value)
                namesofterminalnodestoadd = arrayfun(@(x) sprintf('CF=%0.4g',x),graphopt.value(graphopt.terminalnodes),'UniformOutput',false);
            end
        else % without terminal nodes
            for i=1:ndata, j=c(:,i)>0; g(i,c(j,i))=w(c(j,i)); end %#ok<SPRIX>
            namesofterminalnodestoadd = {};
        end
        dupnames = findduplicates(namesofterminalnodestoadd);
        if ~isempty(dupnames)
            for eachdup = dupnames
                for i=find(ismember(namesofterminalnodestoadd,eachdup))
                    namesofterminalnodestoadd{i} = sprintf('%s (%s)',namesofterminalnodestoadd{i},char(i+96));
                end
            end
        end
        if ~any(g(:)) % Not valid graph
            dispf('WARNING: no valid graph ''%s''',graphopt.prop)
            hgraphtmp = NaN;
        else
            gobj = biograph(g,[{data.(o.print_id)} namesofterminalnodestoadd]);
            hobj=view(gobj); hparentobj = get(hobj.hgAxes,'Parent');
            set(hparentobj,paperprop{:})
            if ~isempty(graphopt.value)
                col = interp1(linspace(0,1,ncol),jet(ncol),graphopt.value/max(graphopt.value));
                for i=1:ndata
                    if ~any(isnan(col(i,:)))
                        set(hobj.Nodes(i),'color',col(i,:))
                        if sum(col(i,:))/3<.4, set(hobj.Nodes(i),'textcolor',[1 1 1]); else set(hobj.Nodes(i),'textcolor',[0 0 0]); end
                    end
                end
                if nterminalnodestoadd>0, set(hobj.Nodes((1:nterminalnodestoadd)+ndata),'Shape','ellipse'); end
            end
            if ~isempty(graphopt.weight)
                set(hobj,'ShowWeights','on')
                for i=1:length(hobj.Edges) % replace NaN by 0
                    if isnan(hobj.Edges(i).Weight), hobj.Edges(i).Weight = 0; end
                end
            end
            if ~isempty(graphopt.color), set(hobj.Nodes,'color',graphopt.color); end
            if ~isempty(graphopt.textcolor), set(hobj.Nodes,'textcolor',graphopt.textcolor); end
            if ~isempty(graphopt.ref), set(hobj.Nodes(graphopt.ref),'color',graphopt.colorref), end
            hgraphtmp = figure('Units','Points','PaperPosition',get(hparentobj,'PaperPosition'),paperprop{:});
            copyobj(hobj.hgAxes,hgraphtmp); set(hgraphtmp,'Units','Pixels');
        end
    end

    %%%% --------------------------------------------------------------------------------------
    %%%% Generate Pareto Chart: ParetoChart(CFvalues(terminalnodes),nodes((terminalnodes),..)
    %%%% valmax: maximum value for color scale
    %%%% defaultlayout: true for default layout (main plot)
    %%%% titletxt: alternative text
    %%%% --------------------------------------------------------------------------------------
    function rankout = ParetoChart(values,nodenames,valmax,defaultlayout,xlabeltxt,titletxt)
        if nargin<3, valmax = max(values); end
        if nargin<4, defaultlayout = true; end
        if nargin<5, xlabeltxt = 'C_F'; end
        if nargin<6, titletxt = ''; end
        nodenames=regexprep(nodenames,'_','\\_'); % protect '_'
        [values,rank] = sort(values,'ascend'); locvaluesmax = max(values);
        col = interp1(linspace(0,1,ncol),jet(ncol),values/valmax);
        if any(isnan(col)), col(any(isnan(col),2),:) = 0; end
        hold on
        for inode=1:length(nodenames)
            barh(inode,values(inode),'FaceColor',col(inode,:))
            labeltxt = nodenames(rank(inode));
            if defaultlayout
                text(0,inode,[labeltxt ' '],'fontsize',10,'HorizontalAlignment','right','VerticalAlignment','middle')
                text(values(inode),inode,sprintf(' %0.3g',values(inode)),'fontsize',10,'HorizontalAlignment','left','VerticalAlignment','middle')
            else
                if sum(col(inode,:))/3<0.4 && values(inode)>.2*locvaluesmax, coltxt = [1 1 1]; else coltxt = [0 0 0]; end
                text(0,inode,labeltxt,'fontsize',7,'HorizontalAlignment','left','VerticalAlignment','middle','color',coltxt,'FontWeight','normal')
            end
        end
        if defaultlayout, xlabel(xlabeltxt,'fontsize',16), end
        if isempty(titletxt), title(strrep(sprintf('%s[\\bf%s\\rm]',o.fmecamainfile,o.fmecasheetname),'_','\_'),'fontsize',12)
        else title(titletxt,'fontsize',10)
        end
        set(gca,'yticklabel',' '), axis tight
        if nargout, rankout = rank; end
    end

    %%%% --------------------------------------------------------------------------------------
    %%%% Generate assembled kinetics from full paths (use a sqrt scale for accuracy)
    %%%% --------------------------------------------------------------------------------------
    function [x,y]=KineticsAssembling(paths)
        ntimes = 512; % 512 for each step
        npaths = length(paths);
        dispf('\nKinetics assembling...')
        screen = dispb('','\tinitialization');
        [x,y] = deal(cell(1,npaths));
        tassemble = clock;
        for ipath = 1:npaths;
            nsteps = length(paths{ipath});
            [x{ipath},y{ipath}] = deal(zeros(ntimes,nsteps));
            tstartkin = 0;
            for istep = 1:nsteps
                screen = dispb(screen,'\t[path=%d/%d][step=%d/%d]\t loading ''%s'' results...',ipath,npaths,istep,nsteps,paths{ipath}{istep});
                if o.ramdisk
                    previousres(1).r = RAMDISK.(o.session).(paths{ipath}{istep}).file;
                else
                    previousres = load(fullfile(o.local,o.outputpath,paths{ipath}{istep}));
                end
                tsqrtfit = linspace(sqrt(previousres.r.t(1)),sqrt(fmecadb.(paths{ipath}{istep}).t),ntimes)';
                y{ipath}(:,istep) = interp1(sqrt(previousres.r.t*previousres.r.timebase),previousres.r.CF,tsqrtfit,o.interp1);
                x{ipath}(:,istep) = tsqrtfit.^2+tstartkin;
                tstartkin = x{ipath}(end,istep);
            end
            x{ipath} = x{ipath}(:)/days; % final time units in days
            y{ipath} = y{ipath}(:);
        end
        screen = dispb(screen,'\t%d kinetics assembled in %0.3g s',npaths,etime(clock,tassemble));
    end


    %%%% --------------------------------------------------------------------------------------
    %%%% ODSpassthrough() based on NOTE10, create 'sim' spreadsheet with any ODS file
    %%%% Currently shorthands are coded with letters before '%'
    %%%  Coded by INRA\Olivier Vitrac - 08/05/14
    %%%  ==> this code is insufficiently tested for production (in particular automatic spanning and shorthands)
    %%%% --------------------------------------------------------------------------------------
    function userbreak = ODSpassthrough()
        autofmeca = argcheck(o.fmecamainfile,defaultautofmecamainfile);           % user property/value
        autofmecakw = argcheck(o.fmecamainfile,[],kwautofmecamainfile);            % user keywords
        autofields = uncell(regexp(fieldnames(o),'^print.*','match'),[],[],true); % customizable fields
        autofieldsid = substructarray(o,autofields);                              % customized values
        autofields_with_shorthand = autofields(~cellfun(@isempty,regexp(autofieldsid,'\%d','start')));
        autofields = cell2struct(autofieldsid,autofields,1);                      % assembled as a structure
        autofieldsid_with_shorthand = substructarray(autofields,autofields_with_shorthand);
        shorthandlist = uncell(regexp(autofieldsid_with_shorthand,'^(.*)\%','tokens'));
        shorhand = cell2struct(autofieldsid_with_shorthand,shorthandlist,1);
        for fauto=fieldnames(autofields)'
            switch autofields.(fauto{1})
                case {o.print_parent o.print_inherit}, defaultauto = '';
                case o.print_id,                       defaultauto = autostepname;
                otherwise,                             defaultauto = NaN;
            end
            if ismember(fauto{1},autofields_with_shorthand) % field to be spanned according to the number of layers
                for iauto=1:autofmeca.nlayers, autofmeca.(sprintf(autofields.(fauto{1}),iauto)) = defaultauto; end
            else autofmeca.(autofields.(fauto{1})) = defaultauto;
            end
        end % next field
        o.inputpath = o.outputpath;
        autofmeca.nfo = sprintf('<small>%s:%s</small>',datestr(now),localname);
        autofmeca = repmat(argcheck(o.fmecamainfile,autofmeca,kwautofmecamainfile,'keep','case'),autofmeca.nsteps,1); % distribute all user values (keep
        % populate values
        for fauto=fieldnames(autofmeca)'
            nauto = length(autofmeca(1).(fauto{1}));
            isfcell    = iscell(autofmeca(1).(fauto{1}));
            isfchar    = ischar(autofmeca(1).(fauto{1}));
            if nauto
                for jauto = 1:autofmeca(1).nsteps
                    % span each step
                    if isfcell, autofmeca(jauto).(fauto{1}) = autofmeca(jauto).(fauto{1}){min(jauto,nauto)};
                    elseif ~isfchar; autofmeca(jauto).(fauto{1}) = autofmeca(jauto).(fauto{1})(min(jauto,nauto));
                    end
                    % span each shorthand (if any)
                    if ismember(fauto,shorthandlist)
                        for iauto=1:autofmeca(1).nlayers
                            autofmeca(jauto).(sprintf(shorhand.(fauto{1}),iauto)) = autofmeca(jauto).(fauto{1})(min(iauto,length(autofmeca(jauto).(fauto{1}))));
                        end
                    end
                end % next span
            end
        end
        o.fmecamainfile = rmfield(autofmeca,intersect(fieldnames(autofmeca),[kwautofmecamainfile';shorthandlist])); %autofmeca;
        for jauto=1:autofmeca(1).nsteps
            if strcmp(o.fmecamainfile(jauto).(o.print_id),autostepname)
                o.fmecamainfile(jauto).(o.print_id) = sprintf(o.fmecamainfile(jauto).(o.print_id),jauto);
            end
        end
        userbreak = false;
        if autofmecakw.make, fmecadb = o; userbreak=true; end
        if autofmecakw.constructor, fmecadb = o.fmecamainfile; userbreak=true; end
    end

end % function fmecaengine


%===============================================================================================================
%% PRIVATE FUNCTIONS (do not share the same workspace as fmecaengine)
%===============================================================================================================

%%%% --------------------------------------------------------------------------------------
%%%% truncateim(imfile) crop and rotate PNG already saved images
%%%% (obsolete function, not used anymore)
%%%% --------------------------------------------------------------------------------------
% function truncateim(imfile,flipon)
%     if nargin<2, flipon = true; end 
%     margin = 100;
%     im = imread(imfile); siz = size(im);
%     imb = min(im,[],3);
%     lim = zeros(2,2);
%     dimlist = 1:2;
%     for dim = dimlist
%         lim(dim,1) = find(min(imb,[],dimlist(mod(dim,2)+1))<255,1,'first');
%         lim(dim,2) = find(min(imb,[],dimlist(mod(dim,2)+1))<255,1,'last');
%     end
%     lim(:,1) = max(lim(:,1)-margin,1);
%     lim(:,2) = min(lim(:,2)+margin,siz(1:2)');
%     im = im(lim(1,1):lim(1,2),lim(2,1):lim(2,2),:);
%     if flipon, im = flipdim(permute(im,[2 1 3]),2); end
%     imwrite(im,imfile,'png');
% end

%%%% --------------------------------------------------------------------------------------
%%%% vec2str(x) print a vector as string
%%%% --------------------------------------------------------------------------------------
function s=vec2str(x,formatx)
    if nargin<2, formatx = '%0.5g'; end
    if iscell(x), s = cellfun(@(xi) vec2str(xi,formatx), x,'UniformOutput',false); return, end
    s = strtrim(sprintf([formatx ' '],x(:)));
    if length(x)>1, s = sprintf('[%s]',s); end
    if size(x,1)>size(x,2), s = [s '''']; end
end

%%%% --------------------------------------------------------------------------------------
%%%% today() returns the current date.
%%%% --------------------------------------------------------------------------------------
function aujourdhui = today 
    c = clock;
    aujourdhui = datenum(c(1),c(2),c(3));
end

%%%% --------------------------------------------------------------------------------------
%%%% protectcell() protects cell fields in a structure
%%%% --------------------------------------------------------------------------------------
function Sp=protectcell(S)
    Sp=S; fn = fieldnames(S)';
    for i=1:numel(S)
        for f=fn
            if iscell(S(i).(f{1}))
                if iscellstr(S(i).(f{1}))
                    tmp = sprintf('%s,',S(i).(f{1}){:}); fmt = '{%s}';
                else
                    tmp = sprintf('%0.8g,',S(i).(f{1}){:}); fmt = '[%s]';
                end
                Sp(i).(f{1}) = sprintf(fmt,tmp(1:end-1));
            end
        end
    end
end

%%%% --------------------------------------------------------------------------------------
%%%% unprotectcell() unprotects cell fields in a structure
%%%% --------------------------------------------------------------------------------------
function S=unprotectcell(Sp)
    S=Sp; fn = fieldnames(Sp)';
    for i=1:numel(S)
        for f=fn
            if ischar(Sp(i).(f{1})) && length(Sp(i).(f{1}))>2
                if strcmp(Sp(i).(f{1})([1 end]),'{}')
                    S(i).(f{1}) = regexp(Sp(i).(f{1})(2:end-1),',','split');
                elseif strcmp(Sp(i).(f{1})([1 end]),'[]')
                    S(i).(f{1}) = str2double(regexp(Sp(i).(f{1})(2:end-1),',','split'));
                end
            end
        end
    end
end

%%%% --------------------------------------------------------------------------------------
%%%% memsize() generates memory size with proper prefix
%%%% 
function pn = memsize(n,ndigits,unit)
if nargin<2, ndigits = 3; end
if nargin<3, unit = 'B'; end
    pfix = {'' 'k' 'M' 'G' 'T' 'P' 'E'};
    irange = floor((log(n)/log(2))/10);
    if irange<1
        pn = 'cleared data';
    else
        pn = sprintf(['%0.' num2str(ndigits) 'g %s%s'],n/2.^(10*irange),pfix{irange+1},unit);
    end
end


%%%% --------------------------------------------------------------------------------------
%%%% compressresult() compress results (along time) to be used with savememory
%%%%
function rc=compressresult(r,t,ratio)
if nargin<3, ratio = 50; end % time compression only
rc = r;
it = nearestpoint(t,r.t*r.timebase); % targeted time
ind = [1:ratio:it-ratio-1 it-ratio:it+ratio]; % preserve resolution around it
for v={'t' 'C' 'CF' 'fc' 'f' 'days'}, rc.(v{1}) = r.(v{1})(ind); end
it = nearestpoint(t,r.tC*r.timebase); % idem for concentration profiles
ind = [1:ratio:it-ratio-1 it-3:it+3];
for v={'tC' 'Cx'}, rc.(v{1}) = r.(v{1})(ind,:); end
rc.xlayerid = uint16(rc.xlayerid);
rc.iscompressed = true;
end

