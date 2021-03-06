function res = senspatankarC(F,ploton,dispon)
%SENSPATANKAR simulates transfer and reactions through n layers using a modified Patankar Method (see p 45)
%   the dimensionless formulation is similar to SENSN
%   all data are normalized according the reference layer or equivalently according to the layer with the lowest D/a value
%   IT IS THE RESPONSABILITY OF THE USER TO PROVIDE THE APPROPRIATE DIMENSIONLESS NUMBERS
%   a wrapper used for the online version is available in ../www/home/diffusion_1DFVn.m

% MS-MATLAB-WEB 1.0 - 25/09/09 - Olivier Vitrac - rev. 15/02/16

% Revision history
% 01/10/07 improve speed
% 16/03/09 add restart
% 29/04/11 add F.restart.CF
% 26/10/11 replace xmesh/xmesh(end) xmesh/F.lrefc(end) in the interpolation (thanks to Nicolas)
% 08/05/14 method = 'pchip'  for compatibility with Matlab 2014
% 19/10/15 add manage id layers, add interpolation layer by layer (to remove a layer at a given step, set any of properties 'D' 'k' or 'l' to 0
% 20/10/15 fix layerid, capture C0eq
% 21/10/15 check only D<=0 when using a restart file, set layerid and xlayerid (more robust), xlayerid modified to include NaN at interfaces
% 21/10/15 implemented rule: negative concentration forces the layer to be removed
% 22/10/15 restrict k to real layers, and fic C0 CO mixup 
% 23/10/15 separation of iref and iabsref
% 24/10/15 full implementation of senspatankar_restart, fix L correction
% 30/11/15 reverse modifications of 24/10/15 as most of the work is not carried out by senspatankar_wrapper
% 15/12/15 generate a warning in no source found
% 15/02/16 add CF0 as default property

% definitions
global timeout
timeout		= 800; % s
% options		= odeset('RelTol',1e-4,'AbsTol',1e-4,'Stats','yes','Initialstep',1e-5,'Maxstep',.05,'Maxorder',5);
options		= odeset('RelTol',1e-4,'AbsTol',1e-4,'Initialstep',1e-8,'Maxstep',.01,'Maxorder',2);
Fdefault	= 	struct(...
				'Bi'		, 	1e3,...	Biot [hm.L1/D]
				'k'			,	[1 1 1 1],...[0.5 3 2],...	ki, i=1 (layer in contact with the liquid)
                'D'         ,   [1e-16 1e-14 1e-14 1e-14],... diffusion coefficient
                'k0'        ,   1,... 0 = liquid
                'l'         ,   [50 20 10 120]*1e-6,...[50 20 10 120]*1e-6,... m
				'L'			,	200/1800,...	dilution factor (respectively to iref)
				'C0'		,	[0 500 500 0],...	initial concentration in each layer
				'options'	,	options...
					); % if iref is missing, it is indentified
%lines to be deleted (OV: 09/04/11, incomplete pieces of code)
%                 'kR'        ,   [.1 .1 .1 .1],...
%                 'kR0'       ,   0,...
Fdefault.t	= [0:.00001:.005 .01:.01:.1 .11:.1:5]; %0:.00001:.005; %[0:.00001:.005 .01:.01:.1 .11:.1:5]';
if Fdefault.Bi<10, Fdefault.t = Fdefault.t/(Fdefault.Bi/10); end
method		= 'pchip'; %'cubic';
ploton_default = false;
dispon_default = false;
nmesh_default  = 200; % number of nodes for a layer of normalized thickness 1
nmeshmin_default    = 10;
n_default	= 1e4;
MaxStepmax	= 10;
nstepchoice = 200;
zero = 1000*eps;

% arg check
initon = false;
if ~nargin, initon = true; end
if nargin<1, F = []; end
if nargin<2, ploton = []; end
if nargin<3, dispon = []; end
if isempty(F), F = Fdefault; end
if ~isfield(F,'autotime'), F.autotime = 'on'; end
if ~isfield(F,'n'), F.n = n_default; end
if ~isfield(F,'nmesh'), F.nmesh = nmesh_default; end
if ~isfield(F,'nmeshmin'), F.nmeshmin = nmeshmin_default; end
if ~isfield(F,'options'), F.options = options; end
if ~isfield(F,'CF0'), F.CF0 = 0; end % added 15/02/2016
if ~nargout, ploton=true; dispon=true; end
if isempty(ploton), ploton = ploton_default; end
if isempty(dispon), dispon = dispon_default; end
isrestarrequired = isfield(F,'restart') && ~isempty(F.restart) && isstruct(F.restart) && isfield(F.restart,'x') && isfield(F.restart,'C');

% physical check
% for prop = {'D' 'k' 'C0' 'kR'}; %line to be deleted (OV: 09/04/11, incomplete pieces of code)
% if isrestarrequired, proptocheck = {'D' 'k' 'l'}; else proptocheck = {'D' 'k' 'C0' 'l'}; end % implemented on 21/10/2015
proptocheck = {'D' 'k' 'C0' 'l'};
m = max(cellfun(@(p) length(F.(p)),proptocheck)); % m = inf;
isavalidlayersubmitted = true(1,m);
for prop = proptocheck
    if strcmp(prop{1},'C0'), ok = (F.(prop{1})>=0);
    else                     ok = (F.(prop{1})>0);
    end
    %F.(prop{1}) = F.(prop{1})(ok); % not required
    isavalidlayersubmitted(~ok) = false;
    m = min(m,length(F.(prop{1})));
end
% check for negative concentrations (they code for layers to remove)
% before 30/11/15: ireallayers = find(F.C0(1:m)>=0); % layers are always counted from left to right
ireallayers = find(isavalidlayersubmitted);
F.m = length(ireallayers);
% end check (added section on 21/10/2015)

if initon
    res = Fdefault;
    if dispon, disp('... init mode'), end
    return
end

% renormalization (fields X1->Xn)
F.k = F.k/F.k0; F.k0 = 1;   % by convention
a = F.D(ireallayers)./F.k(ireallayers);
if isfield(F,'iref')
    iref = F.iref; %ireallayers(F.iref); % fixed on 30/11/2015
else
    [crit,iref] = min( a./F.l(ireallayers) );
    F.iref = iref;
end
F.a = a./a(iref);
iabsref = ireallayers(iref);
F.lengthscale = F.l(iabsref);   
F.lref  = F.l(ireallayers)./F.l(iabsref);
F.lrefc = cumsum(F.lref);
F.C0    = F.C0(ireallayers);
% %%% section removed OV: 30/11/2015 (not required anymore with new standards)
% if isfield(F,'hasbeenwrapped') && F.hasbeenwrapped
%     timescale = F.l(iabsref)^2/F.D(iabsref);
%     F.t = F.t *  F.timescale/timescale; % rescaling when the reference layer changes
%     if isrestarrequired
%         F.L = F.L *  F.l(iabsref)/F.restart.lengthscale; % rescaling when the reference layer changes
%     end
% end
F.l     = F.l(ireallayers);
F.D     = F.D(ireallayers);
F.k     = F.k(ireallayers);
F.iabsref = iabsref;
% F.kR    = F.kR(1:m); %line to be deleted (OV: 09/04/11, incomplete pieces of code)

% Interpolated times
if strcmpi(F.autotime,'on')
	ti		= linspace(min(F.t),max(F.t),F.n)';
else
	ti		= F.t;
end
MaxStepmax = max(MaxStepmax,ceil(F.t(end)/nstepchoice));

% ID of layers (before 30/11/15)
% if isrestarrequired
%     layerid = F.restart.layerid(ireallayers);
% else
%     layerid = ireallayers;
% end
layerid = ireallayers;


% check if restrictions applied %added 24/01/07
if isfield(F,'ivalid')
    F.ivalid = F.ivalid(ismember(F.ivalid,layerid)); %F.ivalid(F.ivalid<m)% modified OV 21/10/2015
    F.a = F.a(F.ivalid);
    F.lref = F.lref(F.ivalid); % normalized lentghs
    F.lrefc = F.lrefc(F.ivalid);
    F.C0 = F.C0(F.ivalid);
    F.l = F.l(F.ivalid);
    F.D = F.D(F.ivalid);
    F.k = F.k(F.ivalid);
    F.kR = F.kR(F.ivalid);
    m = length(F.ivalid);
    F.m = m;
    layerid = layerid(F.ivalid);
end

% initial concentration in the food 'revision 15/02/2016)
CF0 = F.CF0; % default initial concentration in F

% equilibrium value 'revision 15/02/2016)
% Note that L = lref/l0 with liref = li/lref (read senspantankar_wrapper: S.L = S.Ltotal * S.l(iabsref) / sum(S.l) )
C0eq = (F.CF0 + sum(F.lref*F.L.*F.C0)) /(1+sum((F.k0./F.k .* F.lref*F.L)));
if C0eq<=0
    if isrestarrequired
        C0eq = F.restart.C0eq;
    else
        dispf('\n%s',repmat('=',1,48))
        dispf('%s::\tWARNING\n\tall %d layers are empty (no source terms)!!!\n\tPlease check (C0eq forced to 1)',mfilename,m)
        dispf('\n%s',repmat('=',1,48))
        C0eq = 1;
    end
end
F.peq = F.k0 * C0eq;

% mesh generation
X = ones(F.m,1);
for i=2:F.m
    X(i) = X(i-1)*(F.a(i-1)*F.lref(i))/(F.a(i)*F.lref(i-1));
end
X = max(F.nmeshmin,ceil(F.nmesh*X/sum(X)));
X = round((X/sum(X))*F.nmesh); % update
F.nmesh = sum(X); % roundoff
xmesh    = zeros(F.nmesh,1);
D        = xmesh; % diffusion coefficients
k        = xmesh; % activity coefficients
de       = xmesh; % distance to the next interface in the east direction
dw       = xmesh; % distance to the next interface in the west direction
C0       = xmesh; % initial concentration
xlayerid       = xmesh;
j = 1; x0 = 0;
for i=1:F.m
    ind = j+(0:X(i)-1);
    de(ind) = F.lref(i)/(2*X(i));
    dw(ind) = F.lref(i)/(2*X(i));
    D(ind)  = F.D(i)/F.D(F.iref);
    k(ind)  = F.k(i);
    C0(ind) = F.C0(i)/C0eq;
    xmesh(ind) = linspace(x0+dw(ind(1)),F.lrefc(i)-de(ind(end)),X(i));
    x0 = F.lrefc(i);
    j = ind(end)+1;
    xlayerid(ind) = layerid(i);
end

% use a previous solution (if any)
if isrestarrequired
    if ~isfield(F.restart,'method'), F.restart.method = 'linear'; end
    % bulk interpolation (before 19/10/2015)
    %C0 = interp1(F.restart.x/F.restart.x(end),F.restart.C,xmesh/F.lrefc(end),F.restart.method)/C0eq;
    % LAYER BY LAYER INTERPOLATION (after 19/10/2015)
    % TIP: F.restart.id (from previous simulation), realid(from current simulation)
    C0 = zeros(F.nmesh,1);
    for i=1:F.m
        iold = find(F.restart.xlayerid==layerid(i)); % <--- we assume that id are well preserved between steps
        inew = find(xlayerid==layerid(i));           % <--- current layers
        if isempty(iold)
            C0(inew) = F.C0(i)/C0eq;
        else
            xold = (F.restart.x(iold)-F.restart.x(iold(1)))/(F.restart.x(iold(end))-F.restart.x(iold(1))); %<-- dimensionless 0=begin 1=end
            xnew = (xmesh(inew)-xmesh(inew(1))) / (xmesh(inew(end))-xmesh(inew(1))); %<-- dimensionless 0=begin 1=end
            C0(inew) = interp1(xold,F.restart.C(iold),xnew,F.restart.method)/C0eq;   %<-- interpolation from old values and positions
        end
    end
    % end of layer by layer interpolation
    if isfield(F.restart,'CF'), CF0 = F.restart.CF/C0eq; end
end

% equivalent conductances
he = zeros(F.nmesh,1); hw = he;
hw(1) = 1/( (F.k0/k(1))/(F.Bi) + dw(1)/(D(1))   ); % pervious contact
for i=2:F.nmesh
    hw(i) = 1/( (de(i-1)/D(i-1))*(k(i-1)/k(i)) + dw(i)/D(i)  );
end
% for i=1:F.nmesh-1
%     he(i) = hw(i+1); %flux continuity
% end
he(1:F.nmesh-1) = hw(2:F.nmesh); %flux continuity
he(end) = 0; % impervious BC
% control (for debug)
% clf, hold on
% plot(xmesh,zeros(size(xmesh)),'ro')
% plot(xmesh+de,zeros(size(xmesh)),'^')
% plot(xmesh-dw,zeros(size(xmesh)),'v')
% line(repmat(F.lrefc,2,1),repmat(ylim',1,F.m),'color','k')

% Assembling
A = zeros(F.nmesh+1,F.nmesh+1);
%R = zeros(F.nesmh+1,F.nesmh+1); % line to be deleted (OV: 09/04/11, incomplete pieces of code)
% fluid phase = node 0 (position 1)
A(1,1:2) = F.L*hw(1) * [-F.k0/k(1)
                         1           ]';
%R = F.L *  % line to be deleted (OV: 09/04/11, incomplete pieces of code)
% node 1 (position 2)
A(2,1:3) = 1/(dw(1)+de(1)) * [ hw(1)*F.k0/k(1)
                                      -hw(1)-he(1)*k(1)/k(2)
                                       he(1) ]';                     
% node i<n (position i+1)
for i=2:F.nmesh-1
    A(i+1,i:i+2) = 1/(dw(i)+de(i)) * [ hw(i)*k(i-1)/k(i)
                                      -hw(i)-he(i)*k(i)/k(i+1)
                                       he(i) ]';
end
% node n (position n+1)
i = F.nmesh;
A(end,end-1:end) = 1/(dw(i)+de(i)) * [ hw(i)*k(i-1)/k(i)
                                      -hw(i)]';
                                                               
% integration
dCdt = @(t,C)(A*C);

function rate = dCdt_opt(t,C)
rate  = [ ...
    A{1}(1)*C(1) + A{2}(1)*C(2) ;...
    A{1}(2:end-1).*C(2:end-1) + A{2}(2:end).*C(3:end) + A{3}(1:end-1).*C(1:end-2) ;...
    A{1}(end)*C(end) + A{3}(end)*C(end-1) ...
    ];
end

% J = @(t,C)(A);
% F.options.Jacobian = J;
if F.nmesh<400
    F.options.Vectorized = 'on';
    [t,C] = ode15s(dCdt,F.t,[CF0;C0],F.options); % integration: [t,C] = ode15s(dCdt,F.t,[0;C0],F.options);
else % accelerated procedure
    F.options.Vectorized = 'off';
    A = {diag(A,0) diag(A,1) diag(A,-1)};
    [t,C] = ode15s(@dCdt_opt,F.t,[CF0;C0],F.options); % integration: [t,C] = ode15s(@dCdt_opt,F.t,[0;C0],F.options);
end

CF = C(:,1);
C  = C(:,2:end);

% interpolation at each interface
Ce = zeros(length(t),F.nmesh);
Cw = zeros(length(t),F.nmesh);
for i=1:length(t)
    Ce(i,1:end-1) = C(i,1:end-1) - (de(1:end-1).*he(1:end-1).*( k(1:end-1)./k(2:end) .* C(i,1:end-1)' - C(i,2:end)' ) ./ D(1:end-1) )';
    Ce(i,end)     = C(i,end-1);
    Cw(i,2:end)   = C(i,2:end)   + (dw(2:end)  .*hw(2:end)  .*( k(1:end-1)./k(2:end) .* C(i,1:end-1)' - C(i,2:end)' ) ./ D(2:end)   )';
    Cw(i,1)       = C(i,1)       +  dw(1)       *hw(1)       *( F.k0       /k(1)      * CF(i)         - C(i,1)      )  / D(1);
end
Cfull = reshape([Cw;C;Ce],length(t),3*F.nmesh);
xw = xmesh-dw+zero;
xe = xmesh+de-zero;
xfull = [xw';xmesh';xe']; xfull = xfull(:);
kfull = [k';k';k']; kfull = kfull(:);
xlayerid = [NaN(1,F.nmesh);xlayerid';NaN(1,F.nmesh)]; xlayerid = xlayerid(:);

% outputs
res.C = interp1(t,trapz(xfull,Cfull,2)*C0eq,ti,method)/xfull(end); % av conc
res.t = ti; % time base
res.p = NaN; %interp1(t,repmat(kfull',length(t),1).*Cfull*C0eq,ti,method); % to fast calculations
res.peq = F.peq;
res.C0eq = C0eq;
res.V  = F.lrefc(end); %*F.l(F.iref);
res.C0 = C0*C0eq;
res.F  = F;
res.x  = xfull; %*F.l(F.iref);
res.Cx = Cfull*C0eq; %interp1(t,Cfull*C0eq,ti,method);
res.tC = t;
res.CF = interp1(t,CF*C0eq,ti,method);
res.fc = res.CF/F.L;
res.f  = interp1(t,hw(1) * ( F.k0/k(1) * CF - C(:,1) ) * C0eq,ti,method);
res.timebase = res.F.l(res.F.iref)^2/(res.F.D(res.F.iref));
res.layerid = layerid;
res.xlayerid = xlayerid;

end

% example
% F	= 	struct(...
% 				'Bi'		, 	1e3,...	Biot [hm.L1/D]
% 				'k'			,	[5 1],...[0.5 3 2],...	ki, i=1 (layer in contact with the liquid)
%                 'D'         ,   [1e-14 1e-14],... diffusion coefficient
%                 'k0'        ,   1,... 0 = liquid
%                 'l'         ,   [50 100]*1e-6,...[50 20 10 120]*1e-6,... m
% 				'L'			,	1/10,...	dilution factor (respectively to iref)
% 				'C0'		,	[0 500],...	initial concentration in each layer
%                 't'         ,   [0 10] ...
% 					); % if iref is mission, it is indentified
% day=24*3600;
% tunit = res.timebase/day;
% tbase = res.t*tunit;
% tsamp = res.tC*tunit;
% plot(tbase,res.CF)
% plot(res.x,res.Cx')