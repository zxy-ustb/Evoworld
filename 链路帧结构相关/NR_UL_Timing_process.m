function [signal_out, channel_fading] = NR_UL_Timing_process(n_snr, userID, transmit_signal, n_frame, n_slot, cur_time)
% NR_UL_Timing_process
% 作用：
% 1) 校验当前是否为上行slot
% 2) 将输入波形统一整理为 [Nt x Nsamp]
% 3) 施加整数采样级定时偏移
% 4) 调用现有 wireless_channel

globals_declare;

[n_cell, n_user] = getUserIndexfromID(userID);
if isempty(n_cell) || isempty(n_user)
    error('NR_UL_Timing_process: invalid userID.');
end

if ~isfield(user_para{n_cell,n_user}, 'nr') || isempty(user_para{n_cell,n_user}.nr)
    error('NR_UL_Timing_process: user_para{%d,%d}.nr not configured.', n_cell, n_user);
end
if ~isfield(cell_para{1,n_cell}, 'nr') || isempty(cell_para{1,n_cell}.nr)
    error('NR_UL_Timing_process: cell_para{1,%d}.nr not configured.', n_cell);
end

nrCell = cell_para{1,n_cell}.nr;
nrUe   = user_para{n_cell,n_user}.nr;

if ~isfield(nrCell, 'runtime') || isempty(nrCell.runtime)
    error('NR_UL_Timing_process: missing cell NR runtime. Please call sim_config_compute_nr first.');
end

if isfield(nrCell.runtime, 'current_effective_link_type')
    linkType = nrCell.runtime.current_effective_link_type;
else
    linkType = nrCell.runtime.current_link_type;
end

% ------------------------------------------------------------
% 1) 非上行slot：直接输出零接收波形
% ------------------------------------------------------------
NtUe = user_para{n_cell,n_user}.UeAntennaNum;

if ~strcmpi(linkType, 'UPLINK')
    txTmp = local_normalize_ul_waveform(transmit_signal, NtUe);
    signal_out = local_zero_rx(n_cell, size(txTmp, 2));
    channel_fading = [];
    return;
end

% ------------------------------------------------------------
% 2) 统一输入维度为 [Nt x Nsamp]
% ------------------------------------------------------------
signal_in = local_normalize_ul_waveform(transmit_signal, NtUe);

% ------------------------------------------------------------
% 3) 施加整数采样级定时偏移
% ------------------------------------------------------------
timingSamples = local_get_timing_offset_samples(nrUe);
signal_in = local_apply_integer_timing_shift(signal_in, timingSamples);

% ------------------------------------------------------------
% 4) 送入无线信道
% ------------------------------------------------------------
[signal_out, channel_fading] = wireless_channel(signal_in, cur_time, 'UPLINK', userID, n_snr, n_frame);

% ------------------------------------------------------------
% 5) 保存运行态
% ------------------------------------------------------------
user_para{n_cell,n_user}.nr.runtime.current_frame = n_frame;
user_para{n_cell,n_user}.nr.runtime.current_slot = n_slot;
user_para{n_cell,n_user}.nr.runtime.ul_timing_offset_samples = timingSamples;
user_para{n_cell,n_user}.nr.runtime.ul_post_timing_waveform = signal_in;
user_para{n_cell,n_user}.nr.runtime.ul_channel_output = signal_out;

if ~isfield(user_para{n_cell,n_user}.nr, 'channel') || isempty(user_para{n_cell,n_user}.nr.channel)
    user_para{n_cell,n_user}.nr.channel = struct;
end
user_para{n_cell,n_user}.nr.channel.last_fading = channel_fading;

end

%% =====================================================================
% local helpers
% ======================================================================

function signal_out = local_zero_rx(n_cell, numSamples)
globals_declare;

Nr = 1;
if exist('uplink_channel_para', 'var') && ~isempty(uplink_channel_para)
    if n_cell <= size(uplink_channel_para,2) && ~isempty(uplink_channel_para{1,n_cell}) ...
            && isfield(uplink_channel_para{1,n_cell}, 'Nr') && ~isempty(uplink_channel_para{1,n_cell}.Nr)
        Nr = uplink_channel_para{1,n_cell}.Nr;
    end
end
signal_out = complex(zeros(Nr, numSamples));
end

function timingSamples = local_get_timing_offset_samples(nrUe)
timingSamples = 0;

candidateFields = { ...
    {'runtime', 'timing_advance_samples'}, ...
    {'runtime', 'timing_offset_samples'}, ...
    {'timing', 'advance_samples'}, ...
    {'timing', 'offset_samples'}, ...
    {'timing_advance_samples'}, ...
    {'timing_offset_samples'}};

for k = 1:length(candidateFields)
    value = local_get_nested_field(nrUe, candidateFields{k});
    if ~isempty(value)
        timingSamples = round(double(value));
        return;
    end
end
end

function value = local_get_nested_field(s, fieldPath)
value = [];
cur = s;
for i = 1:length(fieldPath)
    key = fieldPath{i};
    if ~isstruct(cur) || ~isfield(cur, key) || isempty(cur.(key))
        return;
    end
    cur = cur.(key);
end
value = cur;
end

function signal_in = local_normalize_ul_waveform(signal_in, Nt)
% 将输入统一整理成 [Nt x Nsamp]

if isempty(signal_in)
    signal_in = complex(zeros(Nt,0));
    return;
end

[rSig, cSig] = size(signal_in);

% 单天线特殊情况
if Nt == 1
    if rSig == 1
        % 已经是 [1 x Nsamp]
        return;
    elseif cSig == 1
        % [Nsamp x 1] -> [1 x Nsamp]
        signal_in = signal_in.';
        return;
    end
end

% 已经是 [Nt x Nsamp]
if rSig == Nt
    return;
end

% 如果传成了 [Nsamp x Nt]，自动转置
if cSig == Nt
    signal_in = signal_in.';
    return;
end

error('NR_UL_Timing_process: transmit_signal size mismatch. Expected [%d x Nsamp], got [%d x %d].', ...
    Nt, rSig, cSig);
end

function shifted = local_apply_integer_timing_shift(signal_in, timingSamples)
[Nt, Ns] = size(signal_in);
shifted = complex(zeros(Nt, Ns));

if Ns == 0
    return;
end
if timingSamples == 0
    shifted = signal_in;
    return;
end

if timingSamples > 0
    timingSamples = min(timingSamples, Ns);
    shifted(:, 1:Ns-timingSamples) = signal_in(:, timingSamples+1:Ns);
else
    delaySamples = min(abs(timingSamples), Ns);
    shifted(:, delaySamples+1:Ns) = signal_in(:, 1:Ns-delaySamples);
end
end