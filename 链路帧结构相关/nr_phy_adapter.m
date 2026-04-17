function varargout = nr_phy_adapter(op, varargin)
%NR_PHY_ADAPTER Unified non-Toolbox NR PHY helpers.
%   nr_phy_adapter 是一个统一适配器函数，用于集中调用不依赖 MATLAB 5G Toolbox 的
%   NR 物理层辅助函数。通过此适配器，上层的时隙处理（如 DL_slot_process_nr、
%   UL_slot_process_nr）和解调代码可以避免直接依赖 5G Toolbox 函数，便于切换实现
%   （手工实现或混合实现）。
%
%   输入参数：
%       op       - 字符串，指定要执行的操作类型，不区分大小写。
%                 支持的操作：
%                   'pdsch_indices' - 构建 PDSCH 资源单元索引
%                   'pdsch_dmrs'    - 构建 PDSCH DMRS 索引和符号
%                   'pusch_indices' - 构建 PUSCH 资源单元索引
%                   'pusch_dmrs'    - 构建 PUSCH DMRS 索引和符号
%                   'tbs'           - 计算传输块大小
%       varargin - 变长输入参数列表，具体含义取决于 op 的值。
%
%   输出参数：
%       varargout - 变长输出参数列表，具体含义取决于 op 的值。
%                   通常为 1~3 个输出，包括索引、符号、信息结构体等。
%
%   示例：
%       [pdschIndices, info] = nr_phy_adapter('pdsch_indices', carrier, pdsch);
%       [dmrsIndices, dmrsSymbols, info] = nr_phy_adapter('pdsch_dmrs', carrier, pdsch);
%       tbs = nr_phy_adapter('tbs', mod, layers, numPRB, nrePerPRB, codeRate, xOverhead);

% ========================== 主函数体 ==========================
% 根据操作类型字符串（不区分大小写）分发到具体的辅助函数
switch lower(op)   % 转换为小写，实现大小写不敏感匹配

    % ------------------- PDSCH 资源索引 -------------------
    case 'pdsch_indices'
        % 调用 nr_pdsch_indices_build 函数，该函数手动构建 PDSCH 占用的所有 RE 的线性索引
        % 输入：varargin{1} - carrier 载波配置结构体
        %       varargin{2} - pdsch PDSCH 配置结构体
        % 输出：idx - 线性索引列向量
        %       info - 结构体，包含 NREPerPRB（每 PRB 数据 RE 数）、G（总编码比特数）、符号集等
        [idx, info] = nr_pdsch_indices_build(varargin{1}, varargin{2});
        varargout = {idx, info};   % 将两个输出打包到 varargout 中

    % ------------------- PDSCH DMRS 索引和符号 -------------------
    case 'pdsch_dmrs'
        % 调用 nr_pdsch_dmrs_build 函数，手动构建 PDSCH DMRS 的索引和 QPSK 符号
        % 输入：varargin{1} - carrier 载波配置结构体
        %       varargin{2} - pdsch PDSCH 配置结构体
        % 输出：idx - DMRS 占用的线性索引列向量
        %       sym - 对应的 QPSK 复符号列向量
        %       info - 结构体，包含 DMRSSymbolSet（符号索引）、Comb（梳齿）、Ports（端口）
        [idx, sym, info] = nr_pdsch_dmrs_build(varargin{1}, varargin{2});
        varargout = {idx, sym, info};

    % ------------------- PUSCH 资源索引 -------------------
    case 'pusch_indices'
        % 调用 nr_pusch_indices_build 函数，手动构建 PUSCH 占用的所有 RE 的线性索引
        % 输入：varargin{1} - carrier 载波配置结构体
        %       varargin{2} - pusch PUSCH 配置结构体
        % 输出：idx - 线性索引列向量
        %       info - 结构体，包含 NREPerPRB、G、符号集等信息
        [idx, info] = nr_pusch_indices_build(varargin{1}, varargin{2});
        varargout = {idx, info};

    % ------------------- PUSCH DMRS 索引和符号 -------------------
    case 'pusch_dmrs'
        % 调用 nr_pusch_dmrs_build 函数，手动构建 PUSCH DMRS 的索引和 QPSK 符号
        % 输入：varargin{1} - carrier 载波配置结构体
        %       varargin{2} - pusch PUSCH 配置结构体
        % 输出：idx - DMRS 占用的线性索引列向量
        %       sym - 对应的 QPSK 复符号列向量
        %       info - 结构体，包含 DMRSSymbolSet、Comb、Ports
        [idx, sym, info] = nr_pusch_dmrs_build(varargin{1}, varargin{2});
        varargout = {idx, sym, info};

    % ------------------- 传输块大小计算 -------------------
    case 'tbs'
        % 调用 nr_tbs_compute 函数，计算传输块大小
        % 输入参数顺序：
        %   varargin{1} - modulation  调制方式字符串（如 'QPSK'）
        %   varargin{2} - nLayers     传输层数
        %   varargin{3} - nPRB        分配的 PRB 数量
        %   varargin{4} - nrePerPRB   每个 PRB 中可用于数据的 RE 数
        %   varargin{5} - targetCodeRate  目标码率（如 0.5）
        %   varargin{6} - xOverhead   高层配置的 X 开销
        % 输出：tbs - 传输块大小（整数比特数）
        tbs = nr_tbs_compute(varargin{1}, varargin{2}, varargin{3}, varargin{4}, ...
                             varargin{5}, varargin{6});
        varargout = {tbs};

    % ------------------- 不支持的操作 -------------------
    otherwise
        % 如果 op 不是上述任何一种，抛出错误提示
        error('nr_phy_adapter: unsupported op %s', op);
end

end   % 函数结束