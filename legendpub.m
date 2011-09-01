function [hax_out,hleg_out] = legendpub(hplot,leg,hax,pos,varargin)
% LEGENDPUB display a legend for plots generated by PLOTPUB (almost similar to legend)
%   Syntax: hl = legendpub(hplot,leg)
%           [hl,ho] = legendpub(hplot,leg,[hax/position],legpos,[...])
%   Inputs
%       hplot: handle object created with PLOTPUB (other handles are not accepted)
%       leg: a cell of strings (use circular permutations if some legends are missing)
%       hax: a valid handle for axes to plot the legend (created with AXES or SUBPLOTS)
%           >> the legend can be plotted in any location. When the position is assigned, it is plotted
%              in the current axes.
%       position = 0 (automatic), 1 (top right corner), 2 (top left), 3 (bottom left), 4 (bottom right)(as legend does), -1 (outiside)
%             other positions such as 'north' 'south' 'east' 'west' ... 'northeastoutside' are also accepted
%           >> A callback is setup to maintain the position of the legend "almost" constant (the 16 positions above are considered)
%       legpos = [xstop xstart [xmargin] [ymargin]] with 0<xstop<xstart<1 (relative units)
%             xstop: final position of the line (default = 0.3)
%             xstart: initial position of the text (default = 0.4)
%             xmargin: horizontal margin (default = 0.05)
%             ymargin: vertical margin (default = 0.05)
%       [...] pair properties for text (see TEXT)
%    >> if a previous LEGENDPUB exists, the previous axes are reused in priority
%    >> invalid properties generate an error
%   Outputs
%       hl = handle of the LEGENDPUB object (as hax if it is was initialy defined)
%       ho = handles of the legend object stores as a structure with fields:
%           hleg(i).plot handles of symbols and line for the ith plot
%           hleg(i).text handles for the corresponding text
%    >> to add legends to specific curves, use e.g. hax([1 3 5]) instead of hax
%    >> legendpub replaces any existing legend created with LEGEND or LEGENDPUB
%    >> if a previous LEGENDPUB exist, the new one is exactly display at the former position
%    >> use delete(hl) to remove any prior legend created with LEGENDPUB
%    >> the handle parent axes is stored in the field 'UserData' instead of the field 'Axes' as for LEGEND objects
%    >> the tag of LEGENDPUB objects is 'legendpub'
%
%  See also: plotpub
%
%   Example:
%    x1 = linspace(0,10,1000)';
%    y1 = ncx2pdf(x,4,2);
%    figure, h=plotpub(x1,{y1 2*y1 4*y1 8*y1},{'a-' 's-v'});
%    hp=legendpub(h,{{'reference' 'curve'} '*2' '*4' '*8'},1)

% MS 2.0 - 10/08/07 - Olivier Vitrac - rev. 17/06/08

% history
% 09/08/07 Release candidate
% 10/08/07 update help
% 12/08/07 add position
% 18/08/07 add automatic legends, when leg is omitted (as legend does)
% 18/08/07 optimize the position of text, fix the case of a single legend
% 19/08/07 fix check all handles
% 22/08/07 add the callback 'resizefcn' for legends (created only when the axes are assigned)
% 27/08/07 add subplot(hax) before return
% 20/08/07 use axpandtotrans to calculate the appopriate xlim and ylim
% 05/09/07 fix legend of a single plot with several lines as legend (if ny>1 is replaced by if nlines>1)
% 05/09/07 optimize the positioning of multiple lines using the readonly extent property of text objects
% 17/06/08 fix legend objects for Matlab 7.4 and higher

% TODO list

% callback (to remove: Stretch-to-Fill)
if (nargin==1) && ischar(hplot) && strcmp(hplot,'makesizeconstant')
    makesizeconstant(gcf)
    return
end

% default values
pos_default = [0.3 0.4];
xmargin_default = 0.05;
ymargin_default = 0.05;
prop = struct( 'line',{{'linestyle','linewidth','color'}},...
               'marker',{{'marker','markersize','markeredgecolor','markerfacecolor'}},...
               'text',{{'fontsize','fontname','fontunits','fontweight','fontangle','linewidth','linestyle','backgroundcolor','edgecolor','color','interpreter'}} ...
               ); % list of accepted properties for legends
tagid = 'legendpub';
legendpos = 0; % default legend position for atomatic legend
poslist = {
    'north'
    'south'
    'east'
    'west'
    'northeast'
    'northwest'
    'southeast'
    'southwest'
    'northoutside'
    'southoutside'
    'eastoutside'
    'westoutside'
    'northeastoutside'
    'northwestoutside'
    'southeastoutside'
    'southwestoutside'
    'best'
    'bestoutside' };

% arg check
if nargin<1, error('valid syntax: hleg = legendpub(hplot,leg,[hax,pos,....])'), end
ny = length(hplot);
if nargin<2 || (isempty(leg) && (ischar(leg) || isnumeric(leg)))
    leg = cell(1,ny);
    for i=1:ny, leg{i} = sprintf('data%d',i); end
end
if ~isstruct(hplot) || ~isfield(hplot,'leg') || ~isfield(hplot,'line') || ~isfield(hplot,'marker') || ~isfield(hplot,'text')
    error('invalid handle object, hplot must be created with PLOTPUB')
end
if ~iscell(leg), leg = {leg}; end
if nargin<3, hax = []; end
if nargin<4, pos = []; end
if isempty(pos), pos = pos_default; end
if length(pos)<2 || length(pos)>4,  error('pos must be [xstop xstart] or [xstop xstart xmargin ymargin]'),end
pos = [pos(:)' zeros(1,4-length(pos))+NaN];
if (pos(1)<0) || (pos(2)>1) || (pos(1)>pos(2)), error('invalid pos = [xstop xstart] values :  0<xstop<xstart<1 '),end
if isnan(pos(3)), pos(3) = xmargin_default; end
if isnan(pos(4)), pos(4) = ymargin_default; end

% check if the current axes are valid
currentax = gca;
if strcmp(get(currentax,'Tag'),tagid), currentax = get(currentax,'UserData'); end
if ~ishandle(currentax) || ~strcmp(get(currentax,'type'),'axes'), error('no proper axes detected'), end

% check all handles
allhandlesok = true;
for f=fieldnames(hplot)'
    for i=1:length(hplot)
        if any(hplot(i).(f{1}))
            allhandlesok = allhandlesok & all(ishandle( hplot(i).(f{1})));
        end
    end
end
if  ~allhandlesok, error('some plot handles are invalid'), end

% text legend check
leg = leg(mod(0:ny-1,length(leg))+1);
nlines = 0;
iline = zeros(1,ny);
for i=1:ny
    if ~iscell(leg{i}), leg{i} = {leg{i}}; end
    if i>1, iline(i) = nlines; end
    nlines = nlines + length(leg{i});
end
if nlines == 0, error('no legend to display'), end

% check for previsous legend objects (from Matlab or LEGENPUB)
htmp = find_legend(currentax,'legend'); if any(htmp), delete_legend(htmp), end
htmp = find_legend(currentax,tagid);
if ~isempty(hax)
    if isnumeric(hax) && ismember(hax(1),-1:4); legendpos = hax(1); hax = [];
    elseif ischar(hax) && ismember(hax,poslist);
        legendpos = hax(1); hax = [];
    elseif (~ishandle(hax)) || ~strcmp(get(hax,'type'),'axes')
        error('the provided axes handle is invalid')
    elseif numel(hax)>1
        error('a single axes handle is required')
    end
end
if isempty(hax)
    if any(htmp)
        hax = htmp;
    else % try to create the Matlab legend to retrieve the required dimensions of axes
        % search the longer line
        maxchar = 0; maxline = '';
        for i=1:ny
            for j=1:length(leg{i})
                if length(leg{i}{j})>maxchar
                    maxchar=length(leg{i}{j});
                    maxline = leg{i}(j);
                end
            end
        end
        % temp plot
        hplot_tmp = zeros(nlines,1);
        leg_tmp = repmat(maxline,1,nlines);
        m = [iline nlines]+1;
        for i=1:ny
            hplot_tmp(m(i):m(i+1)-1) = hplot(i).leg(1);
        end
        if ~all(hplot_tmp), error('some handles are invalid in hplot (some plots must have been deleted)'), end
        htmp = legend(hplot_tmp,leg_tmp,legendpos,varargin{:});
        htmpchildren = get(htmp,'children');
        % text object defines: start position and y margin
        % ptmp = get(htmpchildren(3),'position'); pos([2 4]) = ptmp([1 2]); % start position and y margin
        candidates = findobj(htmpchildren(2:end),'flat','type','text');
        valcandidates = arrayfun(@(x)get(x,'position')',candidates,'UniformOutput',false);
        valcandidates = [valcandidates{:}]';
        pos([2 4]) = [max(valcandidates(:,1)) min(valcandidates(:,2))];
        % line object defines: stop position and x margin
        % ptmp = get(htmpchildren(2),'Xdata'); pos([1 3]) = ptmp([2 1]); % stop position and x margin
        candidates = findobj(htmpchildren(2:end),'flat','type','line');
        selected = (arrayfun(@(x)length(get(x,'Xdata')),candidates)==2);
        valcandidates = arrayfun(@(x)get(x,'Xdata')',candidates(selected),'UniformOutput',false);
        valcandidates = [valcandidates{:}]';
        pos([1 3]) = [max(valcandidates(:,2)) min(valcandidates(:,1))]; % stop position and x margin
        % axes definition
        hax = axes('position',get(htmp,'position'),'visible','off','Tag',tagid,'UserData',currentax); %,'DataAspectRatio',[1 1 2],'PlotBoxAspectRatio',[1 1 1]);
        delete_legend(htmp)
    end
    addlegtofig(hax)
end
if length(hax)>1, error('a single axes is expected'), end
if ~ishandle(hax) || ~strcmp(get(hax,'type'),'axes'), error('invalid axes handle, see AXES, SUBPLOTS'), end
childrens = get(hax,'children');
if any(childrens), delete(childrens), end

% plot
hleg = repmat(struct('plot',[],'text',[]),ny,1);
subplot(hax), hold on
for i=1:ny % for each plotted curve
    if nlines>1, yleg = 1-iline(i)/(nlines-1); else yleg=.5; end % normalized positions
    yleg = yleg*(1-2*pos(4))+pos(4); % resizing between 0 and 1
    allobjects = setdiff(fieldnames(hplot),'leg');
    for object = allobjects(:)' % for all valid objects
        if any(hplot(i).(object{1})) && ishandle(hplot(i).(object{1})(1))
            propvalues = get(hplot(i).(object{1})(1),prop.(object{1})); % get current values
            param = reshape({prop.(object{1}){:} propvalues{:}},length(propvalues),2)'; % pairwise property value
            switch object{1}
                case 'line'
                    hleg(i).plot(end+1) = plot([0 pos(1)],[yleg yleg],param{:});
                case 'marker'
                    hleg(i).plot(end+1) = plot(pos(1)/2,yleg,param{:});
                case 'text'
                    txt = get(hplot(i).text(1),'string');
                    hleg(i).plot(end+1) = text(pos(1)/2,yleg,txt,'horizontalalignment','center','verticalalignment','middle',param{:});
                otherwise
                    error('invalid object %s',object{1})
            end
        end
    end % each object
    if any(hleg(i).plot)
        % new method to center the along the first subline
        set(hax,'xlim',[0 1],'ylim',[0 1])
        if nlines>1, yleg = 1-iline(i)/(nlines-1); else yleg=.5; end
        yleg = yleg*(1-2*pos(4))+pos(4); % resizing between 0 and 1
        hleg(i).text(end+1) = text(pos(2),yleg,leg{i},'horizontalalignment','left','verticalalignment','middle',varargin{:});
        nsublines = length(leg{i});
        if nsublines>1
            currentextent = get(hleg(i).text(end),'extent'); % note: read only property
            currentheight = currentextent(4)/nsublines;
            if mod(nsublines,2)
                set(hleg(i).text(end),'position',[pos(2),yleg-floor(nsublines/2)*currentheight]);
            else
                set(hleg(i).text(end),'position',[pos(2),yleg-(floor(nsublines/2)-.5)*currentheight]);
            end
        end
        % old method
%         for j=1:length(leg{i})
%             if nlines>1, yleg = 1-(iline(i)+j-1)/(nlines-1); else yleg=.5; end
%             yleg = yleg*(1-2*pos(4))+pos(4); % resizing between 0 and 1
%             hleg(i).text(end+1) = text(pos(2),yleg,leg{i}{j},'horizontalalignment','left','verticalalignment','middle',varargin{:});
%         end
    end
end
set(hax,'xlim',[0 1],'ylim',[0 1],...set(hax,'xlim',[0 1],'ylim',[0-pos(4) 1+pos(4)],'xlim',[0-pos(3),1+pos(3)],...
    'visible','off','box','off','xticklabel',' ','yticklabel',' ','xtick',[],'ytick',[],'Tag',tagid,'UserData',currentax)

% outputs
subplot(currentax)
if nargout>0, hax_out = hax; end
if nargout>1, hleg_out = hleg; end


% ========================================
% private functions (updated from LEGEND)
% ========================================
% function dx = expandtotrans(e)
% % transform a relative margin e (approx. space [0 1]) into a translation value in [0-dx 0+dx]
% dx = e/(1-2*e);

function delete_legend(leg)
% remove a legend
if ~isempty(leg) && ishandle(leg) && ~strcmpi(get(leg,'beingdeleted'),'on')
    legh = handle(leg);
    delete(legh);
end

function leg = find_legend(ha,type)
% find the legend object, which match the axes with handle ha
parent = get(ha,'Parent');
ax = findobj(get(parent,'Children'),'flat','Type','axes','Tag',type);
leg=[]; k=1;
if strcmp(type,'legend') % Matlab legend
    prop = 'axes';
else % Pub legend
    prop = 'UserData';
end
while k<=length(ax) && isempty(leg)
    if islegend(ax(k),type)
        hax = handle(ax(k));
        if isequal(double(hax.(prop)),ha)
            leg=ax(k);
        end
    end
    k=k+1;
end

function tf=islegend(ax,type)
% true if it is a legend
if strcmp(type,'legend') % Matlab legend
    if length(ax) ~= 1 || ~ishandle(ax), tf=false;
    else tf=isa(handle(ax),'scribe.legend'); end
else % Pub legend
    tf = ishandle(ax) && strcmp(get(ax,'Tag'),'legendpub') && ishandle(get(ax,'UserData'));
end

function addlegtofig(h)
% add some userdata for resizefcn callback
refunits = 'centimeters';
if ishandle(h)
    f = ancestor(h,'figure'); % parent figure handle
    a = get(h,'userdata'); % axes handle
    userdata = purgelegtofig(get(f,'userdata'));
    if ~ismember(h,userdata.handle)
        currentunits_f = get(f,'units'); set(f,'units',refunits)
        currentunits_a = 'normalized'; set(a,'units',refunits)
        currentunits_h = 'normalized'; set(h,'units',refunits)
        pos_f = get(f,'position'); set(f,'units',currentunits_f)
        pos_a = get(a,'position'); set(a,'units',currentunits_a)
        pos_h = get(h,'position'); set(h,'units',currentunits_h)
        userdata.handle(end+1) = h;
        userdata.position(end+1,:)=pos_h;
        [dmin,i,j] = distance(pos_h,pos_a);
        userdata.corners(end+1,:) = [i j];
        userdata.distance(end+1,:) = dmin;
        set(f,'userdata',userdata,'resizefcn','legendpub(''makesizeconstant'')')
    end
else
    error('ADDLEGENDTOFIG: unknown handle')
end

function userdataout = purgelegtofig(userdata)
% purge userdata
if isempty(userdata)
    userdataout = struct('handle',[],'position',[],'corners',[],'distance',[]);
else
    ind = find(ishandle(userdata.handle));
    userdataout = struct('handle',userdata.handle(ind),'position',userdata.position(ind,:),...
        'corners',userdata.corners(ind,:),'distance',userdata.distance);
end

function makesizeconstant(f)
% resizefcn callback
refunits = 'centimeters';
userdata = purgelegtofig(get(f,'userdata'));
currentaxes = gca;
if ~isstruct(userdata) && ~isfield(userdata,'handle') && isfield(userdata,'position') && isfield(userdata,'corners') && isfield(userdata,'distance')
    error('MAKESIZECONSTANT: no valid user data')
elseif ~isempty(userdata.handle)
    currentunits = 'normalized'; 
    for i=1:length(userdata.handle)
        host = get(userdata.handle(i),'userdata'); % axes handle
        set(host,'units',refunits); 
        poshost = get(host,'position');
        set(host,'units',currentunits)
        set(userdata.handle(i),'units',refunits)
        posframe = get(userdata.handle(i),'position');
        pos = coord(userdata.corners(i,2),poshost) + userdata.distance(i,:) +diff(coord([userdata.corners(i,1) 3],posframe));
        set(userdata.handle(i),'position',[pos userdata.position(i,3:4)]);
        set(userdata.handle(i),'units',currentunits)
    end
else
    set(f,'userdata',[],'resizefcn','');
end
subplot(currentaxes)

function x = coord(corner,pos)
% return the coord of corners of frame defined by pos=[posx posy width height])
shift = [ 1 1 ; 0 1 ; 0 0 ; 1 0 ];
x = [pos(1)+shift(corner,1)*pos(3) pos(2)+shift(corner,2)*pos(4)];

function [dmin,i,j] = distance(framepos,hostpos)
% return the minimum distance of a frame into a host frame
[frame,host]=meshgrid(1:4,1:4);
xframe = coord(frame(:),framepos);
xhost  = coord(host(:),hostpos);
d      = xframe-xhost;
[d2min,id] = min(sum(d.^2,2)); % minimum distance
dmin   = d(id,:);  % distance along x and y at the minimum
[j,i]  = ind2sub([4 4],id); % ith corner of frame and jth corner of host