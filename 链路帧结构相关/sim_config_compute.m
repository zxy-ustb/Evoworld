function sim_config_compute(n_unit)
globals_declare;

if strcmpi(frame_cfg.rat_mode,'LTE')
    sim_config_compute_lte(n_unit);
elseif strcmpi(frame_cfg.rat_mode,'NR')
    sim_config_compute_nr(n_unit);
else
    error('Unknown frame_cfg.rat_mode.');
end