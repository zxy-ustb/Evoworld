%filename:sim_config_init.m
%description:
%该函数设置一些固定的默认参数或者初始化在程序中设置的参数
%或者根据配置参数计算一些参数
%后期可以考虑将这里与子帧无关的参数进一步提取出来组成一个文件
%sim_config_base,sim_config_ext,sim_config_compute三个文件
%update note:2009.2.18 created by zhangjianfei
function sim_config_init_lte
globals_declare;
[cell_num,user_num] = size(user_para);
%根据cp类型及子载波间隔计算PRB内子载波数及符号数
for n_cell=1:cell_num
    %设置各小区参数
    cell_para{1,n_cell}.dw_pts_length=[];%unit:Ts
    cell_para{1,n_cell}.up_pts_length=[];%unit:Ts
    cell_para{1,n_cell}.gp_length=[];%unit:Ts
    cell_para{1,n_cell}.current_subframe_pattern=[];
    switch upper(sys_para.sys_bandwidth)
        case '20M'
            cell_para{1,1}.N_RB_DL=100;
            cell_para{1,1}.N_RB_UL=100;
            cell_para{1,n_cell}.N_FFT=2048;
            cell_para{1,n_cell}.normal_cp_length=[160 144];
            cell_para{1,n_cell}.ex_cp_length=[512];%512 for 15k,1024 for 7.5k
            cell_para{1,n_cell}.total_samples=30720;
        case '15M'
            cell_para{1,1}.N_RB_DL=75;
            cell_para{1,1}.N_RB_UL=75;
            cell_para{1,n_cell}.N_FFT=1536;
            cell_para{1,n_cell}.normal_cp_length=[120 108];
            cell_para{1,n_cell}.ex_cp_length=[384];%512 for 15k,1024 for 7.5k
            cell_para{1,n_cell}.total_samples=23040;
        case '10M'
            cell_para{1,1}.N_RB_DL=50;
            cell_para{1,1}.N_RB_UL=50;
            cell_para{1,n_cell}.N_FFT=1024;
            cell_para{1,n_cell}.normal_cp_length=[80 72];
            cell_para{1,n_cell}.ex_cp_length=[256];%512 for 15k,1024 for 7.5k
            cell_para{1,n_cell}.total_samples=15360;
        case '5.0M'
            cell_para{1,1}.N_RB_DL=25;
            cell_para{1,1}.N_RB_UL=25;
            cell_para{1,n_cell}.N_FFT=512;
            cell_para{1,n_cell}.normal_cp_length=[40 36];
            cell_para{1,n_cell}.ex_cp_length=[128];%512 for 15k,1024 for 7.5k
            cell_para{1,n_cell}.total_samples=7680;
        case '3.0M'
            cell_para{1,1}.N_RB_DL=15;
            cell_para{1,1}.N_RB_UL=15;
            cell_para{1,n_cell}.N_FFT=256;
            cell_para{1,n_cell}.normal_cp_length=[20 18];
            cell_para{1,n_cell}.ex_cp_length=[64];%512 for 15k,1024 for 7.5k
            cell_para{1,n_cell}.total_samples=3840;
        case '1.4M'
            cell_para{1,1}.N_RB_DL=6;
            cell_para{1,1}.N_RB_UL=6;
            cell_para{1,n_cell}.N_FFT=128;
            cell_para{1,n_cell}.normal_cp_length=[10 9];
            cell_para{1,n_cell}.ex_cp_length=[32];%512 for 15k,1024 for 7.5k
            cell_para{1,n_cell}.total_samples=1920;
        otherwise
            error('wrong system bandwidth');
    end
    cell_para{1,n_cell}.sampling_interval=1/(cell_para{1,1}.sc_spacing*cell_para{1,1}.N_FFT);
    cell_para{1,n_cell}.useful_symbol_time=1/(cell_para{1,1}.sc_spacing);
    cell_para{1,n_cell}.detected_userID_list=[];
    cell_para{1,n_cell}.psch.resource_index=[];
    cell_para{1,n_cell}.ssch.resource_index=[];
    cell_para{1,n_cell}.pbch.resource_index=[];
    cell_para{1,n_cell}.pbch.null_index=[];
    cell_para{1,n_cell}.cell_rs_seq=[];
    cell_para{1,n_cell}.cell_rs_index=[];
    cell_para{1,n_cell}.mbsfn_rs_seq=[];
    cell_para{1,n_cell}.mbsfn_rs_index=[];
    cell_para{1,n_cell}.phich.enable_group=[];
    cell_para{1,n_cell}.phich.group_seq_mark=[];
    cell_para{1,n_cell}.phich.REG_set=[];
    cell_para{1,n_cell}.pcfich.REG_set=[];
    cell_para{1,n_cell}.pdcch.REG_set=[];
    cell_para{1,n_cell}.pdcch.startPos=[];
    cell_para{1,n_cell}.pdcch.aggreLevel=[];
    cell_para{1,n_cell}.pdcch.origBitsLen=[];
    cell_para{1,n_cell}.pdcch.RNTI_list=[];
    cell_para{1,n_cell}.pdcch.UeTxAntSelection=[];
    %%
    
    cp_type=cell_para{1,n_cell}.cp_type;
    FS_type=cell_para{1,n_cell}.frame_type;
    sc_spacing=cell_para{1,n_cell}.sc_spacing;
    ap_num=cell_para{1,n_cell}.BS_antenna_port_num;
    UL_DL_config=cell_para{1,n_cell}.UL_DL_config;
    switch upper(cp_type)
        case 'NORMAL'
            cell_para{1,n_cell}.Nsc_RB=12;
            cell_para{1,n_cell}.N_DL_symb=7;
            cell_para{1,n_cell}.N_UL_symb=7;
        case 'EXTENDED'
            switch round(sc_spacing/7.5e3)
                case 2
                    cell_para{1,n_cell}.Nsc_RB=12;
                    cell_para{1,n_cell}.N_DL_symb=6;
                    cell_para{1,n_cell}.N_UL_symb=6;
                case 1
                    cell_para{1,n_cell}.Nsc_RB=24;
                    cell_para{1,n_cell}.N_DL_symb=3;
                otherwise
                    error('subcarrier spacing not supported at present.');
            end
        otherwise
            error('cp type not supported at present.');
    end
    cell_para{1,n_cell}.pdcch.reg_num=[];
    load(cell_para{1,n_cell}.phich.external_source_filename);
    phich_enable_group = length(phich_para.enable_group);
    for n_user=1:user_num
        user_para{n_cell,n_user}.prach.n_RA_PRB=[];% 用户PRACH实际所在位置
        user_para{n_cell,n_user}.pdsch.VRB_flag=[];
        user_para{n_cell,n_user}.pdsch.DataRE_IndexSet=[];%cell,每根天线一个index集合
        user_para{n_cell,n_user}.pdsch.PRB_index_set=[];
        user_para{n_cell,n_user}.pdsch.coding_scheme={'TURBO','TURBO'};
%         user_para{n_cell,n_user}.pdsch.coding_rate={1/3,1/3};
        user_para{n_cell,n_user}.pdsch.crc_type='LTE-CRC24A';%'LTE-CRC24B','LTE-CRC16','LTE-CRC8'
        user_para{n_cell,n_user}.pdsch.crc_length = 24;
        user_para{n_cell,n_user}.pusch.VRB_flag=[];
        user_para{n_cell,n_user}.pusch.DataRE_IndexSet=[];
        user_para{n_cell,n_user}.pusch.PilotRE_IndexSet=[];
        user_para{n_cell,n_user}.pusch.AckRi_X_index=[];
        user_para{n_cell,n_user}.pusch.AckRi_Y_index=[];%应当在编码的时候获取,在扰码的时候也可以获得
        %下面这个参数暂时没有使用
        user_para{n_cell,n_user}.pusch.mimo_mode='MU-MIMO';%'MU-MIMO'将来可能支持多种上行模式?
        user_para{n_cell,n_user}.pusch.coding_scheme={'TURBO','TURBO'};
%         user_para{n_cell,n_user}.pusch.coding_rate={1/3,1/3};
        user_para{n_cell,n_user}.pusch.crc_type='LTE-CRC24A';%'LTE-CRC24B','LTE-CRC16','LTE-CRC8','NULL'
        user_para{n_cell,n_user}.pusch.crc_length = 24;
        user_para{n_cell,n_user}.pdsch.cw_rawbits_size=[];%速率匹配后大小
        user_para{n_cell,n_user}.pdsch.ndata_size = {};
        user_para{n_cell,n_user}.pdsch.K_size = {};
        user_para{n_cell,n_user}.pdsch.CC_size = {};
        user_para{n_cell,n_user}.pdsch.L_size = [];
        %初始化BF.weight权值，根据N_RB_DL的大小
        user_para{1,n_user}.pdsch.BF_vector=zeros(cell_para{1,1}.BS_phy_antenna_num,cell_para{1,1}.N_RB_DL,cell_para{1,1}.BS_antenna_port_num);
       user_para{1,n_user}.pdsch.BF_timing = -1E6*ones(1,cell_para{1,1}.N_RB_DL);
        % 新增加天线加权矩阵的配置cell_para{1,1}.ap_mapping_table，这个矩阵的维度为：
        % 基站天线端口数X基站天线数，
        % 注意8天线配置时情况，这个值不随传输模式变化，只是针对控制信道的，不针对PDSCH
        % 因此不考虑BF情况,永远按照分集设置此表，BF时不用这个表
      %  antenna_ap_num=floor(cell_para{1,1}.BS_phy_antenna_num/cell_para{1,1}.BS_antenna_port_num);
        %temp1=ones(1,antenna_ap_num); 
        %temp2=zeros(1,antenna_ap_num); 
        %cell_para{1,1}.ap_mapping_table=zeros(cell_para{1,1}.BS_antenna_port_num,cell_para{1,1}.BS_phy_antenna_num);
       % for m1=1:cell_para{1,1}.BS_antenna_port_num        
          %  for m2=1:cell_para{1,1}.BS_antenna_port_num
             %   if m1==m2
                %   cell_para{1,1}.ap_mapping_table(m1,(m2-1)*antenna_ap_num+(1:antenna_ap_num)) =temp1;  
               % else
                  %  cell_para{1,1}.ap_mapping_table(m1,(m2-1)*antenna_ap_num+(1:antenna_ap_num)) =temp2;  
               %end
           % end
        %end

        user_para{n_cell,n_user}.pusch.N_PUSCH_symb=[];
        user_para{n_cell,n_user}.pusch.pilot_sequence=[];
        user_para{n_cell,n_user}.pusch.cw_rawbits_size=[];
        user_para{n_cell,n_user}.pusch.ndata_size = {};
        user_para{n_cell,n_user}.pusch.K_size = {};
        user_para{n_cell,n_user}.pusch.CC_size = {};
        user_para{n_cell,n_user}.pusch.L_size = [];
        %PUCCH计算参数
        user_para{n_cell,n_user}.pucch.S_ns=[];%数据时隙扰码参数,每时隙一个
        user_para{n_cell,n_user}.pucch.pilot_sequence=[];%基序列及相位,不包括oc
        user_para{n_cell,n_user}.pucch.data_sequence=[];
        user_para{n_cell,n_user}.pucch.pilotPOS=[];%导频位置
        user_para{n_cell,n_user}.pucch.dataPOS=[];%数据位置
        user_para{n_cell,n_user}.pucch.pilot_oc=[];%导频OC
        user_para{n_cell,n_user}.pucch.data_oc=[];%数据OC
        user_para{n_cell,n_user}.pucch.n_prb_subframe=[];%频域位置
        user_para{n_cell,n_user}.pucch.ackmiss=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.pucch.ackmiss_flag='NO';
        user_para{n_cell,n_user}.pucch.SR_falsealarm=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.pucch.SR_miss=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.pucch.ack_de='NO';
        %仿真结果统计参数
        %这部分参数在后续升级时需要再考虑
        user_para{n_cell,n_user}.pdcch.errorBlockNum=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.pdcch.errorSrcbitNum=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.pdcch.errorRawbitNum=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.pdcch.totalBlockNum=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.pdcch.totalSrcbitNum=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.pdcch.totalRawbitNum=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.pdcch.BLER=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.pdcch.BER=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.pdcch.rawBER=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.pbch.errorBlockNum=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.pbch.errorSrcbitNum=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.pbch.errorRawbitNum=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.pbch.totalBlockNum=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.pbch.totalSrcbitNum=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.pbch.totalRawbitNum=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.pbch.BLER=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.pbch.BER=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.pbch.rawBER=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.pcfich.errorBlockNum=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.pcfich.totalBlockNum=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.pcfich.BLER=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.phich.errorBlockNum=zeros(sim_para.SNR_NUM,8*phich_enable_group);   
        user_para{n_cell,n_user}.phich.totalBlockNum=zeros(sim_para.SNR_NUM,8*phich_enable_group);   
        user_para{n_cell,n_user}.phich.BLER=zeros(sim_para.SNR_NUM,8*phich_enable_group);
        %结果统计参数
        user_para{n_cell,n_user}.RESULT.totalBlockNum=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.RESULT.totalSrcbitNum=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.RESULT.totalRawbitNum=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.RESULT.errorBlockNum=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.RESULT.errorSrcbitNum=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.RESULT.errorRawbitNum=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.RESULT.totalCQIblockNum=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.RESULT.errorCQIblockNum=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.RESULT.totalRIblockNum=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.RESULT.errorRIblockNum=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.RESULT.totalACKblockNum=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.RESULT.errorACKblockNum=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.pucch.ackmiss=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.pucch.ack_num=zeros(1,sim_para.SNR_NUM);
        user_para{n_cell,n_user}.pucch.dtx_num=zeros(1,sim_para.SNR_NUM);
    
    end
    N_ID_CELL=cell_para{1,n_cell}.cellID;
    [MBSFN_PRB_RS_pattern,UE_PRB_RS_pattern,PDSCH_PRB_RS_pattern,PDSCH_PRB_SP_RS_pattern]...
                = DLcell_RS_pattern(N_ID_CELL);
    cell_para{1,n_cell}.MBSFN_PRB_RS_pattern=[MBSFN_PRB_RS_pattern];
    cell_para{1,n_cell}.UE_PRB_RS_pattern=[UE_PRB_RS_pattern];
    cell_para{1,n_cell}.PDSCH_PRB_RS_pattern=[PDSCH_PRB_RS_pattern];
    cell_para{1,n_cell}.PDSCH_PRB_SP_RS_pattern=[PDSCH_PRB_SP_RS_pattern];
end

