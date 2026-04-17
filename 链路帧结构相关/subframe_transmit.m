function [rx_signal,rx_signal0] = subframe_transmit(n_snr,n_frame,n_unit)
globals_declare;

if strcmpi(frame_cfg.rat_mode,'LTE')
    [rx_signal,rx_signal0] = subframe_transmit_lte(n_snr,n_frame,n_unit);
elseif strcmpi(frame_cfg.rat_mode,'NR')
    [rx_signal,rx_signal0] = subframe_transmit_nr(n_snr,n_frame,n_unit);
else
    error('Unknown frame_cfg.rat_mode.');
end