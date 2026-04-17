function tbs = nr_tbs_compute(modulation, numLayers, nPrb, nRePerPrb, targetCodeRate, xOverhead)
%NR_TBS_COMPUTE Approximate NR TBS calculation without 5G Toolbox.
% This follows the usual NR quantization style closely enough for simulator
% use, while keeping the implementation lightweight.

if nargin < 6 || isempty(xOverhead)
    xOverhead = 0;
end

Qm = local_mod_order(modulation);
numLayers = max(1, round(double(numLayers)));
nPrb = max(0, floor(double(nPrb)));
nRePerPrb = max(0, floor(double(nRePerPrb) - double(xOverhead)));
targetCodeRate = max(0, min(0.99, double(targetCodeRate)));

Ninfo = floor(nPrb * nRePerPrb * Qm * numLayers * targetCodeRate);
if Ninfo <= 0
    tbs = 0;
    return;
end

if Ninfo <= 3824
    n = max(3, floor(log2(Ninfo)) - 6);
    NinfoQ = max(24, 2^n * floor(Ninfo / 2^n));
    tbs = 8 * ceil((NinfoQ + 24) / 8) - 24;
else
    n = max(3, floor(log2(Ninfo - 24)) - 5);
    NinfoQ = max(3840, 2^n * round((Ninfo - 24) / 2^n));
    C = ceil((NinfoQ + 24) / 8424);
    tbs = 8 * C * ceil((NinfoQ + 24) / (8 * C)) - 24;
end

tbs = max(0, floor(tbs));

end

function Qm = local_mod_order(modName)
if isstring(modName)
    modName = char(modName);
end
if iscell(modName)
    modName = modName{1};
end
switch upper(modName)
    case 'BPSK'
        Qm = 1;
    case 'QPSK'
        Qm = 2;
    case '16QAM'
        Qm = 4;
    case '64QAM'
        Qm = 6;
    case '256QAM'
        Qm = 8;
    otherwise
        Qm = 2;
end
end
