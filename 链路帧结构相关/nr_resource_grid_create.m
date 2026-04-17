function txGrid = nr_resource_grid_create(carrier, Nt)
%NR_RESOURCE_GRID_CREATE Create an empty NR resource grid without 5G Toolbox.

if nargin < 2 || isempty(Nt)
    Nt = 1;
end

K = 12 * local_get_field(carrier, 'NSizeGrid', 0);
L = local_symbols_per_slot(carrier);
Nt = max(1, round(double(Nt)));

txGrid = complex(zeros(K, L, Nt));

end

function value = local_get_field(s, name, defaultValue)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
end
end

function L = local_symbols_per_slot(carrier)
if isstruct(carrier)
    if isfield(carrier, 'SymbolsPerSlot') && ~isempty(carrier.SymbolsPerSlot)
        L = carrier.SymbolsPerSlot;
        return;
    end
    if isfield(carrier, 'NSymbols') && ~isempty(carrier.NSymbols)
        L = carrier.NSymbols;
        return;
    end
end
L = 14;
end
