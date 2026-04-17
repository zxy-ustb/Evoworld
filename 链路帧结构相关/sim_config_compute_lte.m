%filename:sim_config_compute.m
%description:
%该函数设置一些固定的默认参数或者初始化在程序中设置的参数
%或者根据配置参数计算一些参数
%后期可以考虑将这里与子帧无关的参数进一步提取出来组成一个文件
%sim_config_base,sim_config_ext,sim_config_compute三个文件
%update note:2009.2.18 created by zhangjianfei
function sim_config_compute_lte(n_subframe)
globals_declare;

[cell_num,user_num] = size(user_para);
%根据cp类型及子载波间隔计算PRB内子载波数及符号数
for n_cell=1:cell_num    
    cp_type=cell_para{1,n_cell}.cp_type;
    FS_type=cell_para{1,n_cell}.frame_type;
    UL_DL_config=cell_para{1,n_cell}.UL_DL_config;
    sc_spacing=cell_para{1,n_cell}.sc_spacing;
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
    N_RB_DL=cell_para{1,n_cell}.N_RB_DL;
    Ng=cell_para{1,n_cell}.phich.Ng;
    mi_table=[2 1 -1 -1 -1 2 1 -1 -1 -1;...
        0 1 -1 -1  1 0 1 -1 -1 1;...
        0 0 -1  1  0 0 0 -1  1  0;...
        1 0 -1  -1 -1 0 0 0 1 1;...
        0 0 -1 -1 0 0 0 0 1 1;...
        0 0 -1 0 0 0 0 0 1 0;...
        1 1 -1 -1 -1 1 1 -1 -1 1];%-1 denote uplink.
    %根据前缀类型及双工类型获取N_PHICH_group值
    switch upper(cp_type)
        case 'NORMAL'
            N_PHICH_group=ceil(Ng*(N_RB_DL/8));
            os_table=[1 1 1 1;1 -1 1 -1;1 1 -1 -1;1 -1 -1 1;j  j  j  j; j -j  j -j; j  j  -j  -j; j  -j  -j  j];%构造正交序列表格
        case 'EXTENDED'
            N_PHICH_group=2*ceil(Ng*(N_RB_DL/8));
            os_table=[1 1; 1 -1;j  j; j  -j];
        otherwise
            error('cp type not defined.');
    end

    if(strcmpi(FS_type,'TYPE2'))
        mi=mi_table(UL_DL_config+1,n_subframe+1);
        if(mi==-1)
           % error('this subframe is a uplink subframe');
        else
            N_PHICH_group=mi*N_PHICH_group;
        end
    end
    cell_para{1,n_cell}.phich.N_PHICH_GROUP=N_PHICH_group;
end

