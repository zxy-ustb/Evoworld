%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%   
% filename:subframe_transmit.m
% description:LTE subframe transmiting
% input:
%         n_snr             scalar          snr index {1,2,...,SNR_NUM}
%         n_frame        scalar          frame index {0,1,...,TotalFrameNum(n_snr)-1}
%         n_subframe  scalar          subframe index {0,1,...,9}
% ourput:
%         rx_signal       Nr x subframe_sample_num 添加噪声的接收信号(Nr为接收端天线数)
%         rx_signal0     Nr x subframe_sample_num 不添加噪声的接收信号
%  calling mode:
%         [rx_signal,rx_signal0] = subframe_transmit(n_snr,n_frame,n_subframe)
%  update note:2008-09-20 created by zjf
%                   2009-07-27  封装函数CM_DL_Timing_process和CM_UL_Timing_process by renbin
%                   2009-08-05   updated by renbin
%
%    
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [rx_signal,rx_signal0] = subframe_transmit_lte(n_snr,n_frame,n_subframe)
globals_declare;
%%
%链路自适应技术,发送参数确定(MIMO,频域调度,HARQ,AMC,功率控制等)
%在本部分处理时,需要用到M1的测量参数

%%
%数据源产生
%需要根据用户发射参数确定数据源产生方法(发送旧数据的新版本
%或者发送新数据),这部分链路目前嵌套在后面链路中

%%
%编码及速率匹配(blocks_transmit),目前嵌套在里面

%%
%根据仿真链路类型及接收天线数确定接收信号维度并进行初始化
link_type=sim_para.sim_link_type;
if(strcmpi(link_type,'DOWNLINK'))
    Nr=downlink_channel_para{1,1}.Nr;
    subframe_sample_num=cell_para{1}.sc_spacing*cell_para{1}.N_FFT/1000;
    rx_signal=zeros(Nr,subframe_sample_num);%临时用2天线处理
    rx_signal0=zeros(Nr,subframe_sample_num);
elseif(strcmpi(link_type,'UPLINK'))
    Nr=uplink_channel_para{1,1}.Nr;
    subframe_sample_num=cell_para{1}.sc_spacing*cell_para{1}.N_FFT/1000;
    rx_signal=zeros(Nr,subframe_sample_num);%临时用2天线处理
    rx_signal0=zeros(Nr,subframe_sample_num);
end

%%
%下面根据上下行作不同的处理
cellID_list=sys_para.cellID_list;
CELL_NUM=length(cellID_list);
cur_time=sim_para.global_subframe_index/1000;
for n_cell=1:CELL_NUM
    subframe_indicator=cell_para{n_cell}.subframe_indicator;
    if( subframe_indicator(n_subframe+1)==1 )
        if strcmpi(sim_para.sim_link_type,'DOWNLINK')
            %%
            %下行处理流程
            N_ID_CELL=cellID_list(n_cell);
            %下行信号处理
            if  cell_para{1,n_cell}.pdsch.isExternalSource
                load(cell_para{1,n_cell}.pdsch.external_source_filename);
                
            end
            
            
            
            transmit_subframe_signal=DL_cell_process(N_ID_CELL,n_frame,n_subframe);%下行小区信号处理模块，包括添加小区公共导频图样、控制信道复合、业务信道复合、小区映射、OFDM调制（cp ifft）等。
            
            
            

            sz= size(transmit_subframe_signal);
            if strcmpi(sim_para.link_run_mode,'RECEIVER_TIME')
                %读取天线数据文件(两列,分别对应实部虚部)
                %假设天线数据按照天线1(30720点)-天线2(30720点)的顺序排列
                TxAntennaSignalFile=sim_para.receiver.TxAntennaSignalFile;
                fid=fopen(TxAntennaSignalFile,'r');
                data = textscan(fid,'%f%f','delimiter','\n');
                ant_num = sz(1);
                antSignal = data{1}+j*data{2};
                total_samples = cell_para{1,n_cell}.total_samples;
                %此种方法的排列方式是输入数据排完一根天线排另外一根天线
                transmit_subframe_signal = reshape(antSignal(1:ant_num*total_samples),[],ant_num).';   
                fclose(fid);                
                sim_para.link_run_mode = 'TESTVECTOR';%修改链路运行模式，输出接收端向量
            end
            %经过无线衰落信道,信道是针对某个用户的
            if strcmpi(sim_para.link_run_mode,'RECEIVER')
                FixedChannel = sim_para.receiver.FixedChannel;
                signal_out = FixedChannel*transmit_subframe_signal;
            else
                
                
                [signal_out,channel_fading]=wireless_channel(transmit_subframe_signal,cur_time,'DOWNLINK',N_ID_CELL, n_snr, n_frame); %通过无线信道  有频偏校正    
                
                
                
            end
            
            %添加高斯噪声,高斯噪声是针对某个用户的
            SNR=sim_para.SNR(n_snr);
            [noise_signal noiseless_signal]=noise_adding(signal_out,SNR);
            %多小区信号叠加在下面完成
            rx_signal=rx_signal+noise_signal;
            rx_signal0=rx_signal0+noiseless_signal;

            % 接收端根据上一帧M1的测量信息在本帧进行下行定时同步控制
            [rx_signal rx_signal0] = CM_DL_Timing_process(n_snr, rx_signal, rx_signal0, cur_time);     
 
        elseif strcmpi(sim_para.sim_link_type,'UPLINK')
            %%
            %上行处理流程
            cell_userID_list=cell_para{1,n_cell}.userID_list;
            cell_userNum=length(cell_userID_list);
            if  cell_para{1,n_cell}.pusch.isExternalSource
                %采用外部信源
                load(cell_para{1,n_cell}.pusch.external_source_filename);
            end

            %小区的调度器
            CM_process_UL(n_cell,n_frame,n_subframe);

            for n_user=1:cell_userNum
                %上行用户信号处理
                userID=user_para{n_cell,n_user}.userID;
                if ~strcmpi(user_para{n_cell,n_user}.enable_UL_channel,'NULL')
                    transmit_signal=UL_user_process(userID,n_subframe);                    
                     if strcmpi(sim_para.link_run_mode,'RECEIVER_TIME')
                        %读取天线数据文件(两列,分别对应实部虚部)
                        %每个用户的数据长度为30720行，排完一个用户再排另一个用户
                        TxAntennaSignalFile=sim_para.receiver.TxAntennaSignalFile;
                        fid=fopen(TxAntennaSignalFile,'r');
                        data = textscan(fid,'%f%f','delimiter','\n');
                        antSignal = data{1}+j*data{2};
                        total_samples = cell_para{1,n_cell}.total_samples;
                        transmit_signal = reshape(antSignal((n_user-1)*total_samples+1:n_user*total_samples),1,[]);
                        fclose(fid);
                        sim_para.link_run_mode = 'TESTVECTOR';%修改链路运行模式，输出接收端向量
                     end
                 
                    % 接收端根据上一帧M1的测量信息在本帧进行上行定时同步控制
                    % 其中包含了“经过无线信道wireless_channel.m”
                    [signal_out, channel_fading] = CM_UL_Timing_process(n_snr, userID, transmit_signal, n_frame, n_subframe, cur_time);                                    
                    
                    rx_signal=rx_signal+signal_out;
                end
            end
            SNR=sim_para.SNR(n_snr);
            [rx_signal rx_signal0]=noise_adding(rx_signal,SNR);
                
            
        end
    end
end % end for n_cell