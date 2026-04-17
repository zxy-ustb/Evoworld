function [PDSCH_PRB_DMRS_pattern,PDSCH_PRB_PTRS_pattern,PUSCH_PRB_DMRS_pattern,CSI_RS_PRB_pattern] = DL_RS_pattern_nr(N_ID_CELL)
% DL_RS_pattern_nr
%该函数用于 生成 NR下行链路中单个物理资源块（PRB）内的参考信号（RS）图样。
% 输出四种参考信号的频域（12 个子载波）与时域（每时隙符号数）位置图样，分别为：
%
%   PDSCH_PRB_DMRS_pattern （下行数据信道解调参考信号） : 12 x Nsym
%   PDSCH_PRB_PTRS_pattern （下行数据信道相位跟踪参考信号）: 12 x Nsym
%   PUSCH_PRB_DMRS_pattern （上行数据信道解调参考信号，用于上下行共用小区参数时的上行参考信号）: 12 x Nsym
%   CSI_RS_PRB_pattern     （信道状态信息参考信号）: 12 x Nsym

globals_declare;

n_cell = getCellIndexfromID(N_ID_CELL);
if isempty(n_cell)
    error('NRcell_RS_pattern: invalid N_ID_CELL.');
end

cellCfg = cell_para{1,n_cell};
if ~isfield(cellCfg,'nr') || isempty(cellCfg.nr)
    error('NRcell_RS_pattern: cell_para{%d}.nr is missing.', n_cell);
end

Nsc_RB = 12;
Nsym = cellCfg.nr.symbols_per_slot;

PDSCH_PRB_DMRS_pattern = zeros(Nsc_RB,Nsym);
PDSCH_PRB_PTRS_pattern = zeros(Nsc_RB,Nsym);
PUSCH_PRB_DMRS_pattern = zeros(Nsc_RB,Nsym);
CSI_RS_PRB_pattern     = zeros(Nsc_RB,Nsym);

userID_list = cellCfg.userID_list;
if isempty(userID_list)
    cell_para{1,n_cell}.nr.runtime.PDSCH_PRB_DMRS_pattern = PDSCH_PRB_DMRS_pattern;
    cell_para{1,n_cell}.nr.runtime.PDSCH_PRB_PTRS_pattern = PDSCH_PRB_PTRS_pattern;
    cell_para{1,n_cell}.nr.runtime.PUSCH_PRB_DMRS_pattern = PUSCH_PRB_DMRS_pattern;
    cell_para{1,n_cell}.nr.runtime.CSI_RS_PRB_pattern = CSI_RS_PRB_pattern;
    return;
end

% 优先找当前 runtime 中 active 的 UE；若没有，则退回第一个启用 UE 做模板
[ueCfgPdsch, ueCfgPusch] = local_pick_template_users(n_cell,user_num_from_cell(user_para,n_cell),user_para);

% ======================================================================
% 1. PDSCH DMRS
% ======================================================================
if ~isempty(ueCfgPdsch) && isfield(ueCfgPdsch.nr,'pdsch') && isfield(ueCfgPdsch.nr.pdsch,'dmrs')

    dmrsCfg = ueCfgPdsch.nr.pdsch.dmrs;

    if isfield(ueCfgPdsch.nr.pdsch,'runtime') && isfield(ueCfgPdsch.nr.pdsch.runtime,'active') ...
            && ueCfgPdsch.nr.pdsch.runtime.active == 1 && ~isempty(ueCfgPdsch.nr.pdsch.runtime.DMRSSymbolSet)
        dmrsSymSet = ueCfgPdsch.nr.pdsch.runtime.DMRSSymbolSet;
    elseif isfield(ueCfgPdsch.nr.pdsch,'derived') && isfield(ueCfgPdsch.nr.pdsch.derived,'DMRSSymbolSet')
        dmrsSymSet = ueCfgPdsch.nr.pdsch.derived.DMRSSymbolSet;
    else
        dmrsSymSet = local_pdsch_dmrs_symbols(ueCfgPdsch.nr.pdsch.SymbolAllocation,dmrsCfg);
    end

    if dmrsCfg.DMRSConfigurationType == 1
        comb = [1 3 5 7 9 11];
    else
        comb = [1 4 7 10];
    end

    if isfield(dmrsCfg,'DMRSPortSet') && ~isempty(dmrsCfg.DMRSPortSet)
        flag = 100 + dmrsCfg.DMRSPortSet(1);
    else
        flag = 100;
    end

    for is = 1:length(dmrsSymSet)
        s = dmrsSymSet(is) + 1;
        if s>=1 && s<=Nsym
            PDSCH_PRB_DMRS_pattern(comb,s) = flag;
        end
    end
end

% ======================================================================
% 2. PDSCH PTRS
% ======================================================================
if ~isempty(ueCfgPdsch) && isfield(ueCfgPdsch.nr,'pdsch') && isfield(ueCfgPdsch.nr.pdsch,'ptrs')

    ptrsCfg = ueCfgPdsch.nr.pdsch.ptrs;

    if isfield(ptrsCfg,'enable') && strcmpi(ptrsCfg.enable,'YES')

        if isfield(ueCfgPdsch.nr.pdsch,'runtime') && isfield(ueCfgPdsch.nr.pdsch.runtime,'active') ...
                && ueCfgPdsch.nr.pdsch.runtime.active == 1 && ~isempty(ueCfgPdsch.nr.pdsch.runtime.PTRSSymbolSet)
            ptrsSymSet = ueCfgPdsch.nr.pdsch.runtime.PTRSSymbolSet;
        elseif isfield(ueCfgPdsch.nr.pdsch,'derived') && isfield(ueCfgPdsch.nr.pdsch.derived,'PTRSSymbolSet')
            ptrsSymSet = ueCfgPdsch.nr.pdsch.derived.PTRSSymbolSet;
        else
            if isfield(ueCfgPdsch.nr.pdsch,'derived') && isfield(ueCfgPdsch.nr.pdsch.derived,'DMRSSymbolSet')
                dmrsSymSet = ueCfgPdsch.nr.pdsch.derived.DMRSSymbolSet;
            else
                dmrsSymSet = local_pdsch_dmrs_symbols(ueCfgPdsch.nr.pdsch.SymbolAllocation,ueCfgPdsch.nr.pdsch.dmrs);
            end
            ptrsSymSet = local_ptrs_symbols(ueCfgPdsch.nr.pdsch.SymbolAllocation,dmrsSymSet,ptrsCfg);
        end

        % 单 PRB 模板里固定选第 2 个子载波作为 PTRS 占位
        ptrsSC = local_ptrs_sc_index(ptrsCfg);;
        for is = 1:length(ptrsSymSet)
            s = ptrsSymSet(is) + 1;
            if s>=1 && s<=Nsym
                PDSCH_PRB_PTRS_pattern(ptrsSC,s) = 3000;
            end
        end
    end
end

% ======================================================================
% 3. PUSCH DMRS
% ======================================================================
if ~isempty(ueCfgPusch) && isfield(ueCfgPusch.nr,'pusch') && isfield(ueCfgPusch.nr.pusch,'dmrs')

    dmrsCfg = ueCfgPusch.nr.pusch.dmrs;

    if isfield(ueCfgPusch.nr.pusch,'runtime') && isfield(ueCfgPusch.nr.pusch.runtime,'active') ...
            && ueCfgPusch.nr.pusch.runtime.active == 1 && ~isempty(ueCfgPusch.nr.pusch.runtime.DMRSSymbolSet)
        dmrsSymSet = ueCfgPusch.nr.pusch.runtime.DMRSSymbolSet;
    elseif isfield(ueCfgPusch.nr.pusch,'derived') && isfield(ueCfgPusch.nr.pusch.derived,'DMRSSymbolSet')
        dmrsSymSet = ueCfgPusch.nr.pusch.derived.DMRSSymbolSet;
    else
        dmrsSymSet = local_pusch_dmrs_symbols(ueCfgPusch.nr.pusch.SymbolAllocation,dmrsCfg);
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
            PUSCH_PRB_DMRS_pattern(comb,s) = flag;
        end
    end
end

% ======================================================================
% 4. CSI-RS（占位）
% ======================================================================
if isfield(cellCfg.nr,'csirs') && isfield(cellCfg.nr.csirs,'runtime') && isfield(cellCfg.nr.csirs.runtime,'active') ...
        && cellCfg.nr.csirs.runtime.active == 1

    if ~isempty(cellCfg.nr.csirs.runtime.SymbolSet)
        symSet = cellCfg.nr.csirs.runtime.SymbolSet;
    else
        symSet = 3;  % 默认第4个符号（0-based）
    end

    for is = 1:length(symSet)
        s = symSet(is) + 1;
        if s>=1 && s<=Nsym
            CSI_RS_PRB_pattern(1,s) = 4000;
        end
    end
end

% 保存到 runtime 缓存
cell_para{1,n_cell}.nr.runtime.PDSCH_PRB_DMRS_pattern = PDSCH_PRB_DMRS_pattern;
cell_para{1,n_cell}.nr.runtime.PDSCH_PRB_PTRS_pattern = PDSCH_PRB_PTRS_pattern;
cell_para{1,n_cell}.nr.runtime.PUSCH_PRB_DMRS_pattern = PUSCH_PRB_DMRS_pattern;
cell_para{1,n_cell}.nr.runtime.CSI_RS_PRB_pattern = CSI_RS_PRB_pattern;

end

%% ======================================================================
% local helpers
% ======================================================================

function [ueCfgPdsch, ueCfgPusch] = local_pick_template_users(n_cell,user_num,user_para)
ueCfgPdsch = [];
ueCfgPusch = [];

% 优先取当前 runtime active 的用户
for n_user = 1:user_num
    if isempty(user_para{n_cell,n_user}) || ~isfield(user_para{n_cell,n_user},'nr')
        continue;
    end
    ue = user_para{n_cell,n_user};

    if isempty(ueCfgPdsch) && isfield(ue.nr,'pdsch') && isfield(ue.nr.pdsch,'runtime') ...
            && isfield(ue.nr.pdsch.runtime,'active') && ue.nr.pdsch.runtime.active == 1
        ueCfgPdsch = ue;
    end

    if isempty(ueCfgPusch) && isfield(ue.nr,'pusch') && isfield(ue.nr.pusch,'runtime') ...
            && isfield(ue.nr.pusch.runtime,'active') && ue.nr.pusch.runtime.active == 1
        ueCfgPusch = ue;
    end
end

% 若当前 slot 没有 active 用户，则退回第一个 enable 的用户
for n_user = 1:user_num
    if isempty(user_para{n_cell,n_user}) || ~isfield(user_para{n_cell,n_user},'nr')
        continue;
    end
    ue = user_para{n_cell,n_user};

    if isempty(ueCfgPdsch) && isfield(ue.nr,'pdsch') && isfield(ue.nr.pdsch,'enable') ...
            && strcmpi(ue.nr.pdsch.enable,'YES')
        ueCfgPdsch = ue;
    end

    if isempty(ueCfgPusch) && isfield(ue.nr,'pusch') && isfield(ue.nr.pusch,'enable') ...
            && strcmpi(ue.nr.pusch.enable,'YES')
        ueCfgPusch = ue;
    end
end
end

function n = user_num_from_cell(user_para,n_cell)
if isempty(user_para)
    n = 0;
    return;
end
n = size(user_para,2);
end

function dmrs_sym = local_pdsch_dmrs_symbols(symAlloc,dmrs)
startSym = symAlloc(1);
nSym = symAlloc(2);
dataSymSet = startSym:(startSym+nSym-1);

if isfield(dmrs,'enable') && strcmpi(dmrs.enable,'NO')
    dmrs_sym = [];
    return;
end

l0 = dmrs.DMRSTypeAPosition;
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

dmrs_sym = cand(ismember(cand,dataSymSet));
if dmrs.DMRSLength == 2
    dmrs_sym = unique([dmrs_sym dmrs_sym+1]);
    dmrs_sym = dmrs_sym(ismember(dmrs_sym,dataSymSet));
end
end

function dmrs_sym = local_pusch_dmrs_symbols(symAlloc,dmrs)
startSym = symAlloc(1);
nSym = symAlloc(2);
dataSymSet = startSym:(startSym+nSym-1);

if isfield(dmrs,'enable') && strcmpi(dmrs.enable,'NO')
    dmrs_sym = [];
    return;
end

l0 = max(dmrs.DMRSTypeAPosition,startSym);
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

dmrs_sym = cand(ismember(cand,dataSymSet));
if dmrs.DMRSLength == 2
    dmrs_sym = unique([dmrs_sym dmrs_sym+1]);
    dmrs_sym = dmrs_sym(ismember(dmrs_sym,dataSymSet));
end
end

function ptrs_sym = local_ptrs_symbols(symAlloc,dmrsSym,ptrs)
if ~isfield(ptrs,'enable') || strcmpi(ptrs.enable,'NO')
    ptrs_sym = [];
    return;
end

startSym = symAlloc(1);
nSym = symAlloc(2);
dataSymSet = startSym:(startSym+nSym-1);

cand = startSym+1 : ptrs.TimeDensity : (startSym+nSym-1);
cand = setdiff(cand,dmrsSym);
ptrs_sym = cand(ismember(cand,dataSymSet));
end
function ptrsSC = local_ptrs_sc_index(ptrsCfg)
if ~isfield(ptrsCfg,'REOffset') || isempty(ptrsCfg.REOffset)
    reOff = '00';
else
    reOff = ptrsCfg.REOffset;
end

switch reOff
    case '00'
        ptrsSC = 2;
    case '01'
        ptrsSC = 4;
    case '10'
        ptrsSC = 6;
    case '11'
        ptrsSC = 8;
    otherwise
        ptrsSC = 2;
end
end