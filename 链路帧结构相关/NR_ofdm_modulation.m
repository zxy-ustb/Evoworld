function phy_antenna_signal = NR_ofdm_modulation(slotGrid, N_ID_CELL, n_frame, n_slot)
% NR_ofdm_modulation - 手工实现的NR OFDM调制函数（不依赖5G Toolbox）
%
% 功能描述：
%   将频域资源网格（slotGrid）通过OFDM调制转换为时域发射波形。
%   关键特性：
%     1) 显式保留DC子载波空洞（不映射数据），符合NR规范；
%     2) 不做波形归一化，保持数据/DMRS/PTRS之间的相对功率关系；
%     3) 兼容全载波网格（full carrier grid）或激活BWP网格（active BWP grid）输入；
%     4) 支持多天线（3D网格：子载波 × 符号 × 天线）；
%     5) 使用ifftshift确保频域子载波顺序正确（DC在中心）；
%     6) 为每个OFDM符号添加循环前缀（CP长度从配置中获取）。
%
% 输入参数：
%   slotGrid : 频域资源网格，可以是2D矩阵（子载波×符号）或3D矩阵（子载波×符号×天线），
%             也可以是由多个2D矩阵组成的cell数组（每个元素对应一个天线）。
%   N_ID_CELL : 小区ID，用于从全局变量cell_para中索引小区配置。
%   n_frame   : 当前帧号（用于保存到运行时信息）。
%   n_slot    : 当前时隙号（用于保存到运行时信息）。
%
% 输出参数：
%   phy_antenna_signal : 时域发射波形，尺寸为 [Nt, Nsamp]，
%                        Nt为发射天线数，Nsamp为一个时隙的总采样点数（含CP）。

% ========================== 全局变量声明 ==========================
globals_declare;   % 加载全局结构体：cell_para, sys_para, sim_para, frame_cfg等

% ========================== 1. 参数检查与配置提取 ==========================
% 根据小区ID获取小区索引
n_cell = getCellIndexfromID(N_ID_CELL);
if isempty(n_cell)
    error('NR_ofdm_modulation: invalid N_ID_CELL.');
end

% 检查小区是否配置了NR参数
if ~isfield(cell_para{1,n_cell}, 'nr') || isempty(cell_para{1,n_cell}.nr)
    error('NR_ofdm_modulation: NR config missing in cell_para{1,%d}.nr.', n_cell);
end

cellCfg = cell_para{1, n_cell};   % 小区完整配置
nrCfg = cellCfg.nr;               % NR子配置

% 检查必要字段是否存在
if ~isfield(nrCfg, 'cp_lengths') || isempty(nrCfg.cp_lengths)
    error('NR_ofdm_modulation: nr.cp_lengths is missing. Please run sim_config_init_nr first.');
end
if ~isfield(cellCfg, 'N_FFT') || isempty(cellCfg.N_FFT)
    error('NR_ofdm_modulation: cell_para{1,%d}.N_FFT is missing.', n_cell);
end
if ~isfield(nrCfg, 'carrier') || isempty(nrCfg.carrier) || ...
        ~isfield(nrCfg.carrier, 'NSizeGrid') || isempty(nrCfg.carrier.NSizeGrid)
    error('NR_ofdm_modulation: nr.carrier.NSizeGrid is missing.');
end

% ========================== 2. 解析输入资源网格为统一3D格式 ==========================
% 调用局部函数将slotGrid转换为3D数组 [K_subcarriers, L_symbols, N_antennas]
slotGrid3D = local_parse_slot_grid(slotGrid);
[K_in, L, Nt] = size(slotGrid3D);   % K_in: 输入子载波数，L: OFDM符号数，Nt: 天线数

% 提取关键参数
Nfft = cellCfg.N_FFT;                      % FFT点数（例如4096）
cp_lengths = nrCfg.cp_lengths(:).';        % 每个OFDM符号的CP长度（采样点数），行向量
symbols_per_slot = nrCfg.symbols_per_slot; % 每个时隙的OFDM符号数（通常14）
NSizeGrid_carrier = nrCfg.carrier.NSizeGrid; % 载波带宽对应的RB数
Nsc_carrier = 12 * NSizeGrid_carrier;      % 载波总子载波数（不含DC保护带）

% 检查符号数与CP长度数组是否匹配
if L ~= symbols_per_slot
    error('NR_ofdm_modulation: grid symbol number L=%d does not match nr.symbols_per_slot=%d.', L, symbols_per_slot);
end
if length(cp_lengths) ~= L
    error('NR_ofdm_modulation: cp_lengths length (%d) does not match slot symbols (%d).', length(cp_lengths), L);
end

% 载波子载波数必须小于FFT点数，因为需要为DC子载波留出空洞
if Nsc_carrier >= Nfft
    error('NR_ofdm_modulation: carrier subcarriers (%d) must be smaller than N_FFT (%d) because DC hole must be preserved.', Nsc_carrier, Nfft);
end

% ========================== 3. 将输入网格映射到全载波网格 ==========================
% 创建全载波网格（零初始化），尺寸 [全载波子载波数, 符号数, 天线数]
carrierGrid = complex(zeros(Nsc_carrier, L, Nt));

% 情况1：输入网格已经是全载波网格（K_in == Nsc_carrier）
if K_in == Nsc_carrier
    carrierGrid = slotGrid3D;   % 直接使用

% 情况2：输入网格是激活BWP网格（需要映射到载波的特定位置）
elseif isfield(nrCfg, 'active_bwp') && isfield(nrCfg.active_bwp, 'NSizeBWP') ...
        && ~isempty(nrCfg.active_bwp.NSizeBWP) && K_in == 12 * nrCfg.active_bwp.NSizeBWP
    % 检查BWP起始位置配置
    if ~isfield(nrCfg.active_bwp, 'NStartBWP') || isempty(nrCfg.active_bwp.NStartBWP)
        error('NR_ofdm_modulation: active_bwp.NStartBWP is missing.');
    end
    % 获取载波起始RB（默认为0）
    if ~isfield(nrCfg.carrier, 'NStartGrid') || isempty(nrCfg.carrier.NStartGrid)
        NStartGrid = 0;
    else
        NStartGrid = nrCfg.carrier.NStartGrid;
    end
    % 计算BWP相对于载波起始的RB偏移
    startRB = nrCfg.active_bwp.NStartBWP - NStartGrid;
    if startRB < 0
        error('NR_ofdm_modulation: active BWP starts before carrier grid.');
    end
    % 转换为子载波索引（MATLAB 1-based索引）
    startSC = startRB * 12 + 1;
    endSC = startSC + K_in - 1;
    if endSC > Nsc_carrier
        error('NR_ofdm_modulation: active BWP grid exceeds full carrier grid.');
    end
    % 将BWP网格放入载波网格的对应位置
    carrierGrid(startSC:endSC, :, :) = slotGrid3D;

else
    % 不支持的输入网格尺寸
    error(['NR_ofdm_modulation: input grid subcarriers K=%d not supported. ', ...
        'Expected full carrier grid K=%d or active BWP grid K=%d.'], ...
        K_in, Nsc_carrier, local_get_active_bwp_nsc(nrCfg));
end

% ========================== 4. OFDM调制：为每个天线生成时域波形 ==========================
% 计算总采样点数：所有符号的CP长度之和 + 符号数 * FFT点数
Nsamp = sum(cp_lengths) + L * Nfft;
phy_antenna_signal = complex(zeros(Nt, Nsamp));   % 初始化输出波形矩阵（每行一个天线）

% DC子载波在FFT网格中的索引（1-based），Nfft为偶数时DC索引为 Nfft/2+1
dc = Nfft/2 + 1;

% 计算载波子载波在DC两侧的分布：
%   nLower: DC左侧的子载波数量（低频部分）
%   nUpper: DC右侧的子载波数量（高频部分）
nLower = floor(Nsc_carrier/2);
nUpper = Nsc_carrier - nLower;

% 验证映射范围不会超出FFT网格边界
if (dc - nLower) < 1 || (dc + nUpper) > Nfft
    error('NR_ofdm_modulation: centered mapping with DC hole exceeds Nfft range.');
end

% 对每根发射天线分别进行调制
for ia = 1:Nt
    ptr = 1;   % 当前天线波形中的写入指针（采样点索引）
    for isym = 1:L   % 遍历每个OFDM符号
        % 初始化频域网格（Nfft × 1），DC子载波默认为0
        freqGridNfft = complex(zeros(Nfft, 1));

        % 将载波网格中的低频部分映射到DC左侧（不包含DC）
        if nLower > 0
            freqGridNfft(dc-nLower : dc-1) = carrierGrid(1:nLower, isym, ia);
        end
        % 将载波网格中的高频部分映射到DC右侧
        if nUpper > 0
            freqGridNfft(dc+1 : dc+nUpper) = carrierGrid(nLower+1:end, isym, ia);
        end

        % IFFT变换：先ifftshift将频域顺序恢复为MATLAB的IFFT期望顺序（DC在索引1），
        % 然后做Nfft点IFFT，最后乘以sqrt(Nfft)保持功率（对应工具箱的默认行为）
        td = ifft(ifftshift(freqGridNfft), Nfft) * sqrt(Nfft);

        % 获取当前符号的CP长度
        cp = cp_lengths(isym);
        if cp < 0 || cp > Nfft
            error('NR_ofdm_modulation: invalid CP length at symbol %d.', isym);
        end

        % 添加循环前缀：取时域信号的末尾cp个样点拼接到开头
        symSig = [td(end-cp+1:end); td];
        % 将当前符号的时域波形写入输出矩阵（转置为行向量）
        phy_antenna_signal(ia, ptr:ptr+length(symSig)-1) = symSig.';
        % 更新写入指针
        ptr = ptr + length(symSig);
    end
end

% ========================== 5. 保存OFDM调制信息到运行时结构 ==========================
infoWf = struct;
infoWf.SampleRate = nrCfg.sample_rate;          % 采样率（Hz）
infoWf.Nfft = Nfft;                             % FFT点数
infoWf.CPLengths = cp_lengths;                  % 每个符号的CP长度（采样数）
infoWf.WaveformLength = size(phy_antenna_signal, 2); % 总波形长度
infoWf.NSlot = n_slot;                          % 时隙号
infoWf.NFrame = n_frame;                        % 帧号
infoWf.NSubcarriersCarrier = Nsc_carrier;       % 载波子载波总数
infoWf.NSubcarriersInput = K_in;                % 输入网格子载波数
infoWf.Method = 'manual_ifft_cp_dc_hole';       % 调制方法标识

% 将信息存入小区运行时结构体
cell_para{1, n_cell}.nr.runtime.ofdmInfo = infoWf;
cell_para{1, n_cell}.nr.runtime.last_ofdm_waveform = phy_antenna_signal;

end  % 主函数结束

%% ======================= 局部辅助函数 =======================

function grid3D = local_parse_slot_grid(slotGrid)
% 将输入的频域资源网格统一转换为3D数组 [K, L, Nt]
% 支持三种输入类型：
%   1) 2D矩阵（单天线） -> 扩展为3D，天线维度为1
%   2) 3D矩阵（多天线） -> 直接返回
%   3) cell数组，每个元素为2D矩阵（各天线的网格） -> 合并为3D
if iscell(slotGrid)
    % 输入为cell数组：每个cell对应一根天线的2D网格
    Nt = length(slotGrid);
    if Nt == 0
        error('local_parse_slot_grid: empty cell grid.');
    end
    % 获取第一根天线的尺寸（假定所有天线网格尺寸相同）
    [K, L] = size(slotGrid{1});
    grid3D = complex(zeros(K, L, Nt));
    for it = 1:Nt
        if ~ismatrix(slotGrid{it})
            error('local_parse_slot_grid: each cell element must be a KxL matrix.');
        end
        [Ki, Li] = size(slotGrid{it});
        if Ki ~= K || Li ~= L
            error('local_parse_slot_grid: inconsistent antenna grid size.');
        end
        grid3D(:, :, it) = slotGrid{it};
    end
elseif isnumeric(slotGrid)
    % 输入为数值数组
    if ndims(slotGrid) == 2
        % 2D矩阵 -> 单天线，添加天线维度
        [K, L] = size(slotGrid);
        grid3D = reshape(slotGrid, [K, L, 1]);
    elseif ndims(slotGrid) == 3
        % 3D数组 -> 直接使用
        grid3D = slotGrid;
    else
        error('local_parse_slot_grid: numeric slotGrid must be 2D or 3D.');
    end
else
    error('local_parse_slot_grid: unsupported slotGrid type.');
end
end

function nsc = local_get_active_bwp_nsc(nrCfg)
% 获取激活BWP的子载波总数（如果BWP已配置），否则返回-1
if isfield(nrCfg, 'active_bwp') && isfield(nrCfg.active_bwp, 'NSizeBWP') && ~isempty(nrCfg.active_bwp.NSizeBWP)
    nsc = 12 * nrCfg.active_bwp.NSizeBWP;
else
    nsc = -1;   % 表示未配置
end
end