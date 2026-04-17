function [PUSCH_PRB_DMRS_pattern, PUCCH_PRB_DMRS_pattern, SRS_PRB_pattern] = UL_RS_pattern_nr(N_ID_CELL)
% UL_RS_pattern_nr
% Generate one-PRB NR uplink RS templates for runtime cache and debugging.
%
% 修正点：
% 1) 不再直接 switch rt.Format，避免 Format 为空/向量/字符串对象时报错
% 2) 优先从 runtime 读取，失败后回退到配置层 ue.nr.pucch.format
% 3) 与 DL_RS_pattern_nr 保持同样的“runtime优先、配置回退”的风格

globals_declare;

n_cell = getCellIndexfromID(N_ID_CELL);
if isempty(n_cell)
    error('UL_RS_pattern_nr: invalid N_ID_CELL.');
end

cellCfg = cell_para{1,n_cell};
if ~isfield(cellCfg,'nr') || isempty(cellCfg.nr)
    error('UL_RS_pattern_nr: cell_para{%d}.nr is missing.', n_cell);
end

Nsc_RB = 12;
Nsym = cellCfg.nr.symbols_per_slot;

PUSCH_PRB_DMRS_pattern = zeros(Nsc_RB, Nsym);
PUCCH_PRB_DMRS_pattern = zeros(Nsc_RB, Nsym);
SRS_PRB_pattern        = zeros(Nsc_RB, Nsym);

[ueCfgPusch, ueCfgPucch] = local_pick_template_users(n_cell, size(user_para,2), user_para);

%% =====================================================================
% 1. PUSCH DMRS
% ======================================================================
if ~isempty(ueCfgPusch) && isfield(ueCfgPusch.nr,'pusch') && isfield(ueCfgPusch.nr.pusch,'dmrs')

    dmrsCfg = ueCfgPusch.nr.pusch.dmrs;

    if isfield(ueCfgPusch.nr.pusch,'runtime') && isfield(ueCfgPusch.nr.pusch.runtime,'active') && ...
            ueCfgPusch.nr.pusch.runtime.active == 1 && ...
            isfield(ueCfgPusch.nr.pusch.runtime,'DMRSSymbolSet') && ...
            ~isempty(ueCfgPusch.nr.pusch.runtime.DMRSSymbolSet)

        dmrsSymSet = ueCfgPusch.nr.pusch.runtime.DMRSSymbolSet;

    elseif isfield(ueCfgPusch.nr.pusch,'derived') && isfield(ueCfgPusch.nr.pusch.derived,'DMRSSymbolSet')
        dmrsSymSet = ueCfgPusch.nr.pusch.derived.DMRSSymbolSet;

    else
        dmrsSymSet = local_pusch_dmrs_symbols(ueCfgPusch.nr.pusch.SymbolAllocation, dmrsCfg);
    end

    if dmrsCfg.DMRSConfigurationType == 1
        comb = [1 3 5 7 9 11];
    else
        comb = [1 4 7 10];
    end

    if isfield(dmrsCfg,'DMRSPortSet') && ~isempty(dmrsCfg.DMRSPortSet)
        if numel(dmrsCfg.DMRSPortSet) == 1
            flag = 200 + dmrsCfg.DMRSPortSet;
        else
            flag = 200 + dmrsCfg.DMRSPortSet(1);
        end
    else
        flag = 200;
    end

    for is = 1:length(dmrsSymSet)
        s = dmrsSymSet(is) + 1;
        if s>=1 && s<=Nsym
            PUSCH_PRB_DMRS_pattern(comb, s) = flag;
        end
    end
end

%% =====================================================================
% 2. PUCCH DMRS placeholder
% ======================================================================
if ~isempty(ueCfgPucch) && isfield(ueCfgPucch.nr,'pucch')

    % ---- 2.1 runtime ----
    if isfield(ueCfgPucch.nr.pucch,'runtime') && ~isempty(ueCfgPucch.nr.pucch.runtime)
        rt = ueCfgPucch.nr.pucch.runtime;
    else
        rt = struct;
    end

    % ---- 2.2 DMRS symbol set ----
    if isfield(rt,'active') && rt.active == 1 && isfield(rt,'DMRSSymbolSet') && ~isempty(rt.DMRSSymbolSet)
        dmrsSymSet = rt.DMRSSymbolSet;
    else
        dmrsSymSet = [];
    end

    % ---- 2.3 PUCCH format: runtime优先，配置回退 ----
    fmt = local_get_pucch_format(ueCfgPucch, rt);

    % ---- 2.4 根据格式选择占位 comb ----
    switch fmt
        case 1
            comb = [1 3 5 7 9 11];
        otherwise
            comb = [1 5 9];
    end

    % ---- 2.5 写入占位图样 ----
    for is = 1:length(dmrsSymSet)
        s = dmrsSymSet(is) + 1;
        if s>=1 && s<=Nsym
            PUCCH_PRB_DMRS_pattern(comb, s) = 2800;
        end
    end
end

%% =====================================================================
% 3. SRS placeholder
% ======================================================================
% 仅作为调试占位：最后一个符号，每隔1个子载波放一个
SRS_symbol = Nsym;
SRS_PRB_pattern(1:2:end, SRS_symbol) = 3500;

%% =====================================================================
% 4. 保存 runtime cache
% ======================================================================
cell_para{1,n_cell}.nr.runtime.PUSCH_PRB_DMRS_pattern = PUSCH_PRB_DMRS_pattern;
cell_para{1,n_cell}.nr.runtime.PUCCH_PRB_DMRS_pattern = PUCCH_PRB_DMRS_pattern;
cell_para{1,n_cell}.nr.runtime.SRS_PRB_pattern        = SRS_PRB_pattern;

end

%% =====================================================================
% local helpers
% ======================================================================

function [ueCfgPusch, ueCfgPucch] = local_pick_template_users(n_cell, user_num, user_para)
ueCfgPusch = [];
ueCfgPucch = [];

% 优先取当前 runtime active 的用户
for n_user = 1:user_num
    if isempty(user_para{n_cell,n_user}) || ~isfield(user_para{n_cell,n_user},'nr')
        continue;
    end
    ue = user_para{n_cell,n_user};

    if isempty(ueCfgPusch) && isfield(ue.nr,'pusch') && isfield(ue.nr.pusch,'runtime') && ...
            isfield(ue.nr.pusch.runtime,'active') && ue.nr.pusch.runtime.active == 1
        ueCfgPusch = ue;
    end

    if isempty(ueCfgPucch) && isfield(ue.nr,'pucch') && isfield(ue.nr.pucch,'runtime') && ...
            isfield(ue.nr.pucch.runtime,'active') && ue.nr.pucch.runtime.active == 1
        ueCfgPucch = ue;
    end
end

% 若当前 slot 没有 active 用户，则退回第一个 enable 的用户
for n_user = 1:user_num
    if isempty(user_para{n_cell,n_user}) || ~isfield(user_para{n_cell,n_user},'nr')
        continue;
    end
    ue = user_para{n_cell,n_user};

    if isempty(ueCfgPusch) && isfield(ue.nr,'pusch') && isfield(ue.nr.pusch,'enable') && ...
            strcmpi(ue.nr.pusch.enable,'YES')
        ueCfgPusch = ue;
    end

    if isempty(ueCfgPucch) && isfield(ue.nr,'pucch') && isfield(ue.nr.pucch,'enable') && ...
            strcmpi(ue.nr.pucch.enable,'YES')
        ueCfgPucch = ue;
    end
end
end

function dmrs_sym = local_pusch_dmrs_symbols(symAlloc, dmrs)
startSym = symAlloc(1);
nSym = symAlloc(2);
dataSymSet = startSym:(startSym+nSym-1);

if isfield(dmrs,'enable') && strcmpi(dmrs.enable,'NO')
    dmrs_sym = [];
    return;
end

l0 = max(dmrs.DMRSTypeAPosition, startSym);
switch dmrs.DMRSAdditionalPosition
    case 0
        cand = [l0];
    case 1
        cand = [l0 l0+4];
    case 2
        cand = [l0 l0+4 l0+7];
    otherwise
        cand = [l0 l0+3 l0+6 l0+9];
end

dmrs_sym = cand(ismember(cand, dataSymSet));
if dmrs.DMRSLength == 2
    dmrs_sym = unique([dmrs_sym dmrs_sym+1]);
    dmrs_sym = dmrs_sym(ismember(dmrs_sym, dataSymSet));
end
end

function fmt = local_get_pucch_format(ueCfgPucch, rt)
% 从 runtime / config 中提取一个可安全用于 switch 的标量格式

fmtRaw = [];

% runtime.Format
if isfield(rt,'Format') && ~isempty(rt.Format)
    fmtRaw = rt.Format;
elseif isfield(rt,'format') && ~isempty(rt.format)
    fmtRaw = rt.format;
elseif isfield(ueCfgPucch.nr.pucch,'Format') && ~isempty(ueCfgPucch.nr.pucch.Format)
    fmtRaw = ueCfgPucch.nr.pucch.Format;
elseif isfield(ueCfgPucch.nr.pucch,'format') && ~isempty(ueCfgPucch.nr.pucch.format)
    fmtRaw = ueCfgPucch.nr.pucch.format;
end

% 默认格式
if isempty(fmtRaw)
    fmt = 1;
    return;
end

% string -> char
if isstring(fmtRaw)
    if isscalar(fmtRaw)
        fmtRaw = char(fmtRaw);
    else
        fmt = 1;
        return;
    end
end

% cell -> 取第一个元素
if iscell(fmtRaw)
    if isempty(fmtRaw)
        fmt = 1;
        return;
    else
        fmtRaw = fmtRaw{1};
    end
end

% 数值格式
if isnumeric(fmtRaw)
    if isscalar(fmtRaw)
        fmt = double(fmtRaw);
    else
        fmt = double(fmtRaw(1));
    end
    return;
end

% 字符格式，例如 '1' / 'format1' / 'Format1'
if ischar(fmtRaw)
    tok = regexp(fmtRaw, '\d+', 'match', 'once');
    if isempty(tok)
        fmt = 1;
    else
        fmt = str2double(tok);
        if isnan(fmt)
            fmt = 1;
        end
    end
    return;
end

% 兜底
fmt = 1;
end