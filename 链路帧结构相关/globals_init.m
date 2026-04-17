%filename:globals_init.m
%description:该函数实现的是全局函数初始化,内在包含全局声明,在程序中只能在主函数中使用一次
%update note:2008-09-20 created by zjf
globals_declare;
AP_FLAG_TABLE=[0 1 2 3 4 5;100 101 102 103 104 105];%[port_index;flag]天线端口标志位映射表
DL_CONTROL_FLAG=99;
X_PLACEHOLDER=-100;
Y_PLACEHOLDER=100;
%下面几个参数实际应从文本配置或者其它配置文件中读取网络拓扑获知
sys_para=[];
cell_para=[];
user_para=[];
user_data=[];%小区x用户x最大码字数，专门用于保存用户传输的数据,PDSCH/PUSCH

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 新增：统一帧结构配置4.14
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
frame_cfg = [];

% RAT模式：默认 LTE
frame_cfg.rat_mode = 'NR';             % 'LTE' / 'NR'

% 统一处理单元定义
frame_cfg.unit_name = 'SUBFRAME';       % LTE默认处理单元
frame_cfg.mu = 0;                       % LTE等效 mu=0
frame_cfg.scs = 15e3;                   % 默认15kHz
frame_cfg.unit_per_subframe = 1;        % LTE: 1个subframe只含1个处理单元
frame_cfg.unit_per_frame = 10;          % LTE: 10个subframe/10ms frame
frame_cfg.symbols_per_unit = 14;        % LTE normal CP默认14个OFDM符号
frame_cfg.sample_rate = [];
frame_cfg.samples_per_unit = [];
frame_cfg.flexible_slot_as = 'DOWNLINK'; % NR灵活时隙默认按下行处理
frame_cfg.enable_legacy_cm_timing_nr = 'YES'; % NR默认不复用LTE时序控制
frame_cfg.current = [];
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% initiate for CC
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
CC_global_table;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%按照协议36.211 配置 上下行配置表
% (1)--downlink    (-1)--uplink      0--special subframe
%jiangzheng 添加  2009-06-01
UL_DL_config_table = ...
[   1 0 -1 -1 -1 1 0 -1 -1 -1;
    1 0 -1 -1 1 1 0 -1 -1 1;
    1 0 -1 1 1 1 0 -1 1 1;
    1 0 -1 -1 -1 1 1 1 1 1;
    1 0 -1 -1 1 1 1 1 1 1;
    1 0 -1 1 1 1 1 1 1 1;
    1 0 -1 -1 -1 1 0 -1 -1 1];
