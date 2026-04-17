function slotGrid = NR_ofdm_demodulation(rxWaveform, N_ID_CELL, n_frame, n_slot)
% NR_ofdm_demodulation - manual OFDM demodulation matching NR_ofdm_modulation.

globals_declare;

n_cell = getCellIndexfromID(N_ID_CELL);
if isempty(n_cell)
    error('NR_ofdm_demodulation: invalid N_ID_CELL.');
end
if ~isfield(cell_para{1,n_cell},'nr') || isempty(cell_para{1,n_cell}.nr)
    error('NR_ofdm_demodulation: NR config missing.');
end

cellCfg = cell_para{1,n_cell};
nrCfg = cellCfg.nr;
Nfft = cellCfg.N_FFT;
cp_lengths = nrCfg.cp_lengths(:).';
L = nrCfg.symbols_per_slot;
NSizeGrid = nrCfg.carrier.NSizeGrid;
Nsc = 12 * NSizeGrid;

if size(rxWaveform,2) ~= sum(cp_lengths) + L * Nfft
    error('NR_ofdm_demodulation: waveform length does not match one slot.');
end

Nr = size(rxWaveform,1);
slotGrid = complex(zeros(Nsc, L, Nr));

dc = Nfft/2 + 1;
nLower = floor(Nsc/2);
nUpper = Nsc - nLower;
ptr = 1;

for ia = 1:Nr
    ptr = 1;
    for isym = 1:L
        cp = cp_lengths(isym);
        symLen = cp + Nfft;
        symSig = rxWaveform(ia, ptr:ptr+symLen-1).';
        symNoCp = symSig(cp+1:end);
        freqGrid = fftshift(fft(symNoCp, Nfft) / sqrt(Nfft));

        lower = [];
        upper = [];
        if nLower > 0
            lower = freqGrid(dc-nLower:dc-1);
        end
        if nUpper > 0
            upper = freqGrid(dc+1:dc+nUpper);
        end
        slotGrid(:,isym,ia) = [lower; upper];
        ptr = ptr + symLen;
    end
end

info = struct;
info.SampleRate = nrCfg.sample_rate;
info.Nfft = Nfft;
info.CPLengths = cp_lengths;
info.NSlot = n_slot;
info.NFrame = n_frame;
info.NSubcarriers = Nsc;
info.Method = 'manual_remove_cp_fft_dc_hole';
cell_para{1,n_cell}.nr.runtime.last_ofdm_demod_info = info;
end
