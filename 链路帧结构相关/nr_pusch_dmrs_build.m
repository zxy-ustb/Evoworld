function [dmrsIndices, dmrsSymbols, info] = nr_pusch_dmrs_build(carrier, pusch)
%NR_PUSCH_DMRS_BUILD Build NR PUSCH DMRS indices and symbols without Toolbox.
%   该函数手动构建 NR PUSCH 的 DMRS（解调参考信号）资源单元（RE）索引和对应的 QPSK 符号，
%   不依赖 MATLAB 5G Toolbox。它根据载波配置（carrier）和 PUSCH 配置（pusch）生成所有
%   DMRS 占用的 RE 位置及其复数符号。
%
%   输入：
%       carrier - 载波配置结构体，需包含 NSizeGrid（RB 数）、SymbolsPerSlot（可选）、
%                 NTxAnts（可选）、NCellID（可选）等。
%       pusch   - PUSCH 配置结构体，需包含 SymbolAllocation（符号分配）、PRBSet（可选）、
%                 DMRS（DMRS 配置子结构体）等。
%   输出：
%       dmrsIndices  - DMRS 占用的所有 RE 的线性索引（列向量），适用于维度为 [K, L, Nt] 的资源网格。
%       dmrsSymbols  - 对应每个索引的 QPSK 复数值符号（列向量）。
%       info         - 结构体，包含 DMRSSymbolSet（DMRS 符号索引，0-based）、
%                      Comb（频域梳齿子载波索引，1-based）、Ports（端口列表）。

% ========================== 主函数体 ==========================
% 计算总子载波数 K = 12 * RB 总数
K = 12 * carrier.NSizeGrid;
% 获取每个时隙的 OFDM 符号数 L（默认为 14）
L = local_symbols_per_slot(carrier);
% 安全获取 DMRS 配置，若不存在则使用空结构体
dmrsCfg = local_get_field(pusch, 'DMRS', struct);
% 获取 PUSCH 分配的 PRB 集合（0‑based，唯一且按行排列）
prbSet = local_prb_set(pusch, carrier);
% 计算 DMRS 占用的符号位置（0‑based 符号索引）
dmrsSymSet = local_pusch_dmrs_symbols(pusch.SymbolAllocation, dmrsCfg);
% 获取 DMRS 端口集合
ports = local_dmrs_ports(dmrsCfg);
% 确定资源网格的天线平面数：取发射天线数与端口数中的较大者（保证索引不越界）
numPlanes = max(local_get_field(carrier, 'NTxAnts', numel(ports)), numel(ports));
% 根据 DMRS 配置类型获取频域梳齿子载波索引（1‑based，PRB 内）
comb = local_dmrs_comb(dmrsCfg);

% 预分配索引和符号数组（大小按最坏情况估算：PRB 数 × DMRS 符号数 × 梳齿数 × 端口数）
allIdx = zeros(max(1, numel(prbSet) * numel(dmrsSymSet) * numel(comb) * numel(ports)), 1);
allSym = complex(zeros(size(allIdx)));
ptr = 1;   % 当前填充位置的指针

% 三层循环：PRB → DMRS 符号 → 端口
for ip = 1:numel(prbSet)
    prb = prbSet(ip);
    % 计算当前 PRB 内 DMRS 子载波的绝对索引（1‑based，因为 comb 是 1‑based）
    scAbs = prb * 12 + comb;
    for is = 1:numel(dmrsSymSet)
        sym0 = dmrsSymSet(is);          % 0‑based 符号索引
        sym1 = sym0 + 1;                % 1‑based 符号索引（用于 sub2ind）
        for ipt = 1:numel(ports)
            % 天线平面索引：若发射天线数大于端口数，则每个端口映射到不同的天线平面；
            % 否则，多个端口可能映射到同一平面（简化处理，取 min）。
            plane = min(ipt, numPlanes);
            n = numel(scAbs);
            % 将子载波、符号、天线平面组合为线性索引（假设网格为 [K, L, numPlanes]）
            idx = sub2ind([K, L, numPlanes], scAbs(:), sym1 * ones(n,1), plane * ones(n,1));
            allIdx(ptr:ptr+n-1) = idx;
            % 为这些 RE 生成 QPSK 序列（基于端口、符号、PRB 等计算的种子）
            % 偏移量 2000 用于与 PDSCH DMRS（偏移 1000）区分
            allSym(ptr:ptr+n-1) = local_qpsk_sequence(n, local_dmrs_seed(carrier, ports(ipt), sym0, prb, 2000));
            ptr = ptr + n;
        end
    end
end

% 截取实际使用的部分（去除预分配中未填充的尾部）
dmrsIndices = allIdx(1:ptr-1);
dmrsSymbols = allSym(1:ptr-1);
% 返回辅助信息
info = struct('DMRSSymbolSet', dmrsSymSet, 'Comb', comb, 'Ports', ports);

end   % 主函数结束

%% ======================= 局部辅助函数 =======================

function value = local_get_field(s, name, defaultValue)
% 安全地从结构体中获取字段值，若字段不存在或为空则返回默认值
% 输入：s - 结构体，name - 字段名，defaultValue - 默认值
% 输出：字段值或默认值
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
end
end

function L = local_symbols_per_slot(carrier)
% 获取每个时隙的 OFDM 符号数
% 优先使用 carrier.SymbolsPerSlot，其次 carrier.NSymbols，否则默认 14
if isfield(carrier, 'SymbolsPerSlot') && ~isempty(carrier.SymbolsPerSlot)
    L = carrier.SymbolsPerSlot;
elseif isfield(carrier, 'NSymbols') && ~isempty(carrier.NSymbols)
    L = carrier.NSymbols;
else
    L = 14;   % NR 常规 CP 下每时隙固定 14 个符号
end
end

function prbSet = local_prb_set(cfg, carrier)
% 获取 PUSCH 分配的 PRB 集合（0‑based，行向量，唯一）
% 若配置中未指定 PRBSet，则默认使用整个载波带宽的所有 PRB
prbSet = local_get_field(cfg, 'PRBSet', []);
if isempty(prbSet)
    prbSet = 0:(carrier.NSizeGrid-1);
end
prbSet = unique(prbSet(:).');   % 确保为一维行向量且无重复
end

function comb = local_dmrs_comb(dmrsCfg)
% 根据 DMRS 配置类型返回频域梳齿子载波索引（1‑based，PRB 内）
% Type1: 每 PRB 6 个 DMRS 子载波（1,3,5,7,9,11）
% Type2: 每 PRB 4 个 DMRS 子载波（1,4,7,10）
if local_get_field(dmrsCfg, 'DMRSConfigurationType', 1) == 1
    comb = [1 3 5 7 9 11];
else
    comb = [1 4 7 10];
end
end

function ports = local_dmrs_ports(dmrsCfg)
% 获取 DMRS 端口集合。若未指定，默认使用端口 0。
ports = local_get_field(dmrsCfg, 'DMRSPortSet', 0);
ports = ports(:).';   % 确保为行向量
if isempty(ports)
    ports = 0;
end
end

function dmrsSym = local_pusch_dmrs_symbols(symAlloc, dmrs)
% 计算 PUSCH DMRS 占用的符号位置（0‑based 索引）
% 输入：symAlloc - [起始符号, 符号长度]，dmrs - DMRS 配置结构体
% 输出：dmrsSym - DMRS 符号索引数组
startSym = symAlloc(1);
nSym = symAlloc(2);
dataSymSet = startSym:(startSym+nSym-1);   % PUSCH 占用的所有符号

% 若 DMRS 被禁用，返回空
if isfield(dmrs, 'enable') && strcmpi(dmrs.enable, 'NO')
    dmrsSym = [];
    return;
end

% PUSCH 的 TypeA DMRS 起始符号不能早于 PUSCH 起始符号
l0 = max(local_get_field(dmrs, 'DMRSTypeAPosition', startSym), startSym);
% 根据附加位置确定候选 DMRS 符号
switch local_get_field(dmrs, 'DMRSAdditionalPosition', 0)
    case 0
        cand = [l0];
    case 1
        cand = [l0 l0+4];
    case 2
        cand = [l0 l0+4 l0+7];
    otherwise
        cand = [l0 l0+3 l0+6 l0+9];
end
% 只保留落在 PUSCH 符号内的候选
dmrsSym = cand(ismember(cand, dataSymSet));
% 如果是双符号 DMRS，每个位置扩展为连续两个符号
if local_get_field(dmrs, 'DMRSLength', 1) == 2
    dmrsSym = unique([dmrsSym dmrsSym+1]);
    dmrsSym = dmrsSym(ismember(dmrsSym, dataSymSet));
end
end

function seed = local_dmrs_seed(carrier, port, sym0, prb, offset)
% 为每个 DMRS RE 生成伪随机序列种子。
% 种子计算公式：offset + 97*NCellID + 29*port + 13*sym0 + prb
% 该公式用于保证不同小区、端口、符号、PRB 的 DMRS 序列不同。
% 对于 PUSCH，偏移量 offset 通常设为 2000（与 PDSCH 的 1000 区分）。
nCellId = local_get_field(carrier, 'NCellID', 0);
seed = offset + 97 * double(nCellId) + 29 * double(port) + 13 * double(sym0) + double(prb);
end

function seq = local_qpsk_sequence(N, seed)
% 生成 N 个 QPSK 调制符号（归一化功率，即每个符号幅值为 1/√2）。
% 输入：
%   N    - 符号数量
%   seed - 随机种子（保证可重复性）
% 输出：
%   seq  - 复数值列向量，每个元素为 (±1 ± 1i)/√2。
% 实现：生成 2N 个随机比特，奇数为 I 路，偶数为 Q 路，映射为 BPSK 后组合。
s = RandStream('mt19937ar', 'Seed', seed);
b = randi(s, [0 1], 2 * N, 1);
b0 = 1 - 2 * b(1:2:end);   % I 路：0->1, 1->-1
b1 = 1 - 2 * b(2:2:end);   % Q 路：0->1, 1->-1
seq = (b0 + 1i * b1) / sqrt(2);
end