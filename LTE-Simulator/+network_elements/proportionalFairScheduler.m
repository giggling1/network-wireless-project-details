classdef proportionalFairScheduler < network_elements.lteScheduler
% A proportional fair LTE scheduler.
% (c) Josep Colom Ikuno, INTHFT, 2010

   properties
       % See the lteScheduler class for a list of inherited attributes
       alpha
       beta
   end

   methods
       
       % Class constructor.
       % The needed parameters are the following:
       %   - window_size: in order to calculate the eNodeB's past throughput, a time window is used. Specified in TTIs
       %   - alpha: \alpha parameter that is used to calculate the priority P
       %   - beta:  \beta parameter that is used to calculate the priority P
       function obj = proportionalFairScheduler(attached_eNodeB_sector,varargin)
           % Fill in basic parameters (handled by the superclass constructor)
           obj = obj@network_elements.lteScheduler(attached_eNodeB_sector);
           if isempty(varargin)
               obj.alpha = 1;
               obj.beta  = 1;
           elseif length(varargin)==2
               obj.alpha = varargin{1};
               obj.beta  = varargin{2};
           else
               error('Valid constructors are: proportionalFairScheduler(attached_eNodeB_sector)->alpha=1,beta=1 or proportionalFairScheduler(attached_eNodeB_sector,alpha,beta)');
           end
       end
       
       % Print some info
       function print(obj)
           fprintf('Proportional fair scheduler\n');
       end
       
       % Dummy functions required by the lteScheduler Abstract class implementation
       % Add UE (no UE memory, so empty)
       function add_UE(obj,UE_id)
       end
       % Delete UE (no UE memory, so empty)
       function remove_UE(obj,UE_id)
       end
       
       % Schedule the users in the given RB grid
       function schedule_users(obj,RB_grid,attached_UEs,last_received_feedbacks)
           % Power allocation
           % Nothing here. Leave the default one (homogeneous)
           
           RB_grid.size_bits = 0;
           
           % For now use the static tx_mode assignment
           RB_grid.size_bits = 0;
           nCodewords  = RB_grid.nCodewords;
           nLayers     = RB_grid.nLayers;
           tx_mode     = RB_grid.tx_mode;
           current_TTI = obj.clock.current_TTI;
           
           if ~isempty(attached_UEs)
               
               % Fill in P matrix
               P = zeros(size(last_received_feedbacks.CQI,1),size(last_received_feedbacks.CQI,2));
               CQI_efficiency = obj.get_spectral_efficiency(last_received_feedbacks.CQI);
               R_k_RB = sum(180e3*CQI_efficiency/obj.clock.TTI_time,3);  % Requested throughput for all of the spatial streams
               TTI_to_read = max(current_TTI-obj.feedback_delay_TTIs,1); % Realistically read the ACKed throughput
               T_k = zeros(length(attached_UEs),1);
               for u_=1:length(attached_UEs)
                   
                   if isempty(last_received_feedbacks.UE_id)
                       print_log(2,['TTI: ' num2str(current_TTI) '\n']);
                       print_log(2,['UE: ' num2str(attached_UEs(u_).id) '\n']);
                       print_log(2,['eNodeB: ' num2str(attached_UEs(u_).attached_eNodeB.id) '\n']);
                       print_log(2,['sector : ' num2str(attached_UEs(u_).attached_eNodeB.sectors(attached_UEs(u_).attached_sector).id)  '\n']);
                       return;
                   end
                   UE_id = last_received_feedbacks.UE_id(u_);
                   if UE_id~=0
                       UE_avg_throughput = sum(obj.UE_traces(u_).avg_throughput(:,TTI_to_read)); % Mean throughput, averaged with an exponential window)
                       % Set a minimum average throughput of 1 bit/s in
                       % order to avoid too small values that could lead to
                       % Infs
                       if UE_avg_throughput<1
                           UE_avg_throughput = 1;
                       end
                       T_k(u_) = UE_avg_throughput;
                   else
                       T_k(u_) = Inf;
                   end
               end
               T_k_mat = repmat(T_k,[1 RB_grid.n_RB]);
               P = R_k_RB.^obj.alpha ./ T_k_mat.^obj.beta;
               UE_id_list = obj.get_max_UEs(P,last_received_feedbacks.UE_id);
               
               % Fill in RB grid
               RB_grid.user_allocation(:) = UE_id_list;
               
               % CQI assignment. TODO: implement HARQ
               RB_grid_size_bits = 0;
               predicted_UE_BLERs = NaN(nCodewords,length(attached_UEs));
               assigned_UE_RBs    = zeros(1,length(attached_UEs));
               for u_=1:length(attached_UEs)
                   current_UE = attached_UEs(u_);
                   if last_received_feedbacks.feedback_received(u_)
                       
                       UE_CQI_feedback = squeeze(last_received_feedbacks.CQI(u_,:,:));
                       
                       % Do not use RBs with a CQI of 0 (they are lost). Get CQIs to average also
                       [assigned_RBs CQIs_to_average_all UE_scheduled] = obj.filter_out_zero_RBs_and_get_CQIs(RB_grid,nCodewords,UE_CQI_feedback,current_UE);
                       
                       if UE_scheduled
                           % Simplified this piece of code by using the superclass, as all types of scheduler will to make use of it.
                           [assigned_CQI predicted_UE_BLERs(:,u_) estimated_TB_SINR] = obj.get_optimum_CQIs(CQIs_to_average_all,nCodewords);
                           % Signal down the user CQI assignment
                           attached_UEs(u_).eNodeB_signaling.TB_CQI = assigned_CQI;
                           
                           attached_UEs(u_).eNodeB_signaling.nCodewords    = nCodewords;
                           attached_UEs(u_).eNodeB_signaling.nLayers       = nLayers;
                           attached_UEs(u_).eNodeB_signaling.tx_mode       = tx_mode;
                           attached_UEs(u_).eNodeB_signaling.genie_TB_SINR = estimated_TB_SINR;
                       end
                   else
                       % How this right now works: no feedback->CQI of 1
                       UE_scheduled = true;
                       attached_UEs(u_).eNodeB_signaling.TB_CQI(1:nCodewords) = 1;
                       % Signal down the user CQI assignment
                       attached_UEs(u_).eNodeB_signaling.nCodewords    = nCodewords;
                       attached_UEs(u_).eNodeB_signaling.nLayers       = nLayers;
                       attached_UEs(u_).eNodeB_signaling.tx_mode       = tx_mode;
                       attached_UEs(u_).eNodeB_signaling.genie_TB_SINR = NaN;
                       predicted_UE_BLERs(u_) = 0; % Dummy value to avoid a NaN
                   end
                   
                   if UE_scheduled
                       TB_CQI_params = obj.CQI_tables(attached_UEs(u_).eNodeB_signaling.TB_CQI);
                       modulation_order = [TB_CQI_params.modulation_order];
                       coding_rate = [TB_CQI_params.coding_rate_x_1024]/1024;
                       num_assigned_RB  = squeeze(sum(RB_grid.user_allocation==attached_UEs(u_).id));
                       TB_size_bits = floor(RB_grid.sym_per_RB .* num_assigned_RB .* modulation_order .* coding_rate);
                   else
                       num_assigned_RB = 0;
                       TB_size_bits = 0;
                   end
                   
                   attached_UEs(u_).eNodeB_signaling.num_assigned_RBs = num_assigned_RB;
                   attached_UEs(u_).eNodeB_signaling.TB_size = TB_size_bits;
                   attached_UEs(u_).eNodeB_signaling.rv_idx = 0;
                   
                   RB_grid_size_bits = RB_grid_size_bits + TB_size_bits;
                   
                   assigned_UE_RBs(u_) = num_assigned_RB;
               end
               
               RB_grid.size_bits = RB_grid_size_bits;
               
               % TODO: HARQ handling, #streams decision and tx_mode decision. Also power loading
               
               % Store trace
               TTI_idx = obj.attached_eNodeB_sector.parent_eNodeB.clock.current_TTI;
               obj.trace.store(TTI_idx,mean(assigned_UE_RBs),mean(predicted_UE_BLERs(isfinite(predicted_UE_BLERs))));
           end
       end
   end
end 
