function slot_pattern = UL_slot_pattern_nr(N_ID_CELL, n_slot)
% UL_slot_pattern_nr
% Generate current NR uplink slot occupancy pattern for debugging/runtime cache.

globals_declare;
UL_CONTROL_FLAG = 88;

n_cell = getCellIndexfromID(N_ID_CELL);
if isempty(n_cell)
    error('UL_slot_pattern_nr: invalid N_ID_CELL.');
end

cellCfg = cell_para{1,n_cell};
if ~isfield(cellCfg,'nr') || isempty(cellCfg.nr)
    error('UL_slot_pattern_nr: cell_para{%d}.nr is missing.', n_cell);
end

nr = cellCfg.nr;
if ~isfield(nr,'runtime') || isempty(nr.runtime) || ...
        ~isfield(nr.runtime,'current_slot') || isempty(nr.runtime.current_slot) || ...
        nr.runtime.current_slot ~= n_slot
    error('UL_slot_pattern_nr: please call sim_config_compute_nr(n_frame,n_slot) first.');
end

if isfield(nr,'active_bwp') && isfield(nr.active_bwp,'NSizeBWP') && ~isempty(nr.active_bwp.NSizeBWP)
    Nsc = 12 * nr.active_bwp.NSizeBWP;
elseif isfield(nr,'grid') && isfield(nr.grid,'NSubcarriers')
    Nsc = nr.grid.NSubcarriers;
else
    error('UL_slot_pattern_nr: cannot determine number of subcarriers.');
end

Nsym = nr.symbols_per_slot;
slot_pattern = zeros(Nsc, Nsym);

userID_list = cellCfg.userID_list;
for iu = 1:length(userID_list)
    userID = userID_list(iu);
    [u_cell,u_user] = getUserIndexfromID(userID);
    if isempty(u_cell) || isempty(u_user) || isempty(user_para{u_cell,u_user})
        continue;
    end
    ue = user_para{u_cell,u_user};
    if ~isfield(ue,'nr') || isempty(ue.nr)
        continue;
    end

    % PUSCH data and DMRS
    if isfield(ue.nr,'pusch') && isfield(ue.nr.pusch,'runtime') && ...
            isfield(ue.nr.pusch.runtime,'active') && ue.nr.pusch.runtime.active == 1
        if isfield(ue.nr.pusch.runtime,'EffectivePRBSet') && ~isempty(ue.nr.pusch.runtime.EffectivePRBSet)
            prbSet = ue.nr.pusch.runtime.EffectivePRBSet;
        else
            prbSet = ue.nr.pusch.runtime.PRBSet;
        end
        symSet = ue.nr.pusch.runtime.SymbolSet;
        dmrsSymSet = ue.nr.pusch.runtime.DMRSSymbolSet;
        scData = local_prb_to_sc(prbSet, Nsc);

        if ~isempty(scData)
            for is = 1:length(symSet)
                s = symSet(is) + 1;
                if s>=1 && s<=Nsym
                    slot_pattern(scData, s) = userID;
                end
            end
        end

        if isfield(ue.nr.pusch,'dmrs') && ~isempty(ue.nr.pusch.dmrs)
            scDmrs = local_pusch_dmrs_sc(prbSet, ue.nr.pusch.dmrs, Nsc);
            if isfield(ue.nr.pusch.dmrs,'DMRSPortSet') && ~isempty(ue.nr.pusch.dmrs.DMRSPortSet)
                if numel(ue.nr.pusch.dmrs.DMRSPortSet) == 1
                    portFlag = 200 + ue.nr.pusch.dmrs.DMRSPortSet;
                else
                    portFlag = 200 + ue.nr.pusch.dmrs.DMRSPortSet(1);
                end
            else
                portFlag = 200;
            end
            for is = 1:length(dmrsSymSet)
                s = dmrsSymSet(is) + 1;
                if s>=1 && s<=Nsym && ~isempty(scDmrs)
                    slot_pattern(scDmrs, s) = portFlag;
                end
            end
        end
    end

    % PUCCH placeholder occupancy
    if isfield(ue.nr,'pucch') && isfield(ue.nr.pucch,'runtime') && ...
            isfield(ue.nr.pucch.runtime,'active') && ue.nr.pucch.runtime.active == 1
        prbSet = ue.nr.pucch.runtime.PRBSet;
        symSet = ue.nr.pucch.runtime.SymbolSet;
        dmrsSymSet = ue.nr.pucch.runtime.DMRSSymbolSet;
        scSet = local_prb_to_sc(prbSet, Nsc);

        if ~isempty(scSet)
            for is = 1:length(symSet)
                s = symSet(is) + 1;
                if s>=1 && s<=Nsym
                    slot_pattern(scSet, s) = UL_CONTROL_FLAG;
                end
            end

            for is = 1:length(dmrsSymSet)
                s = dmrsSymSet(is) + 1;
                if s>=1 && s<=Nsym
                    % In placeholder mode, use every other RE as DMRS marker.
                    slot_pattern(scSet(1:2:end), s) = 2800;
                end
            end
        end
    end
end

cell_para{1,n_cell}.nr.runtime.current_ul_slot_pattern = slot_pattern;
end

function scSet = local_prb_to_sc(prbSet, Nsc)
if isempty(prbSet)
    scSet = [];
    return;
end
scSet = zeros(length(prbSet)*12,1);
ptr = 1;
for ip = 1:length(prbSet)
    base = prbSet(ip) * 12;
    cur = base + (1:12);
    cur = cur(cur>=1 & cur<=Nsc);
    ncur = length(cur);
    if ncur > 0
        scSet(ptr:ptr+ncur-1) = cur(:);
        ptr = ptr + ncur;
    end
end
scSet = scSet(1:ptr-1);
end

function scDmrs = local_pusch_dmrs_sc(prbSet, dmrsCfg, Nsc)
if isempty(prbSet)
    scDmrs = [];
    return;
end
if dmrsCfg.DMRSConfigurationType == 1
    comb = [1 3 5 7 9 11];
else
    comb = [1 4 7 10];
end
scDmrs = zeros(length(prbSet)*length(comb),1);
ptr = 1;
for ip = 1:length(prbSet)
    base = prbSet(ip) * 12;
    cur = base + comb;
    cur = cur(cur>=1 & cur<=Nsc);
    ncur = length(cur);
    if ncur > 0
        scDmrs(ptr:ptr+ncur-1) = cur(:);
        ptr = ptr + ncur;
    end
end
scDmrs = scDmrs(1:ptr-1);
end
