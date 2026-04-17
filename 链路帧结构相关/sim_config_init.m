function sim_config_init
globals_declare;

if strcmpi(frame_cfg.rat_mode,'LTE')
    sim_config_init_lte;
elseif strcmpi(frame_cfg.rat_mode,'NR')
    sim_config_init_nr;
else
    error('Unknown frame_cfg.rat_mode.');
end