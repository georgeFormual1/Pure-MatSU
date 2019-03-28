function [sim_output] = simulation(sim_options)
% SIMULATION Top-level simulation function
% Sets up the simulation framework, instantiates objects and contains the main simulation loop.
% Do NOT edit this file, use the simulation_options function instead!
% DO run this function to start the simulation.
%
% Syntax:  [sim_output] = simulation(simulation_options())
%
% Inputs:
%    sim_options - Simulation settings, output of simulation_options() function
%
% Outputs:
%    sim_output - simulation result struct with memebers:
%       array_time_states - 1xN array, with the timestamps of the control input values
%       array_states - kxN array, where k is the size of the serialized state vector, N is the number of simulation frames
%       array_time_inputs - 1xM array, with the timestamps of the control input values
%       array_inputs - lxM array, where l is the number of vehicle control inputs (commonly 4) and M is the number of
%       input time frames. Commonly M is either equal to N, or 1 less.
%
% Other m-files required: Vehicle, Gravity, Environment, Propulsion, Aerodynamics, Kinematics, VehcileState,
% draw_aircraft, draw_forces, draw_states
% Subfunctions: none
% MAT-files required: none
%
% See also: simulation_options

% Created at 2018/05/15 by George Zogopoulos-Papaliakos
% Last edit at 2018/06/06 by George Zogopoulos-Papaliakos

% Enable warnings
warn_state = warning('on','all');

%% Initialize the simulation

fprintf('Initializing simulation options...\n');

% Initialize the simulation components, bar the controller
supervisor = Supervisor(sim_options);

% If sim_options.controller.type == 1, then the aircraft must be trimmed
if sim_options.controller.type==1
    trimmer = Trimmer(sim_options); % Instantiate the trimming object
    trimmer.calc_trim();
    trim_state = trimmer.get_trim_state(); % Get the trim state
    init_vec_euler = trim_state.get_vec_euler(); % Re-set the initialization state to the trim states
    sim_options.init.vec_euler(1:2) = init_vec_euler(1:2);
    sim_options.init.vec_vel_linear_body = trim_state.get_vec_vel_linear_body();
    sim_options.init.vec_vel_angular_body = trim_state.get_vec_vel_angular_body();
    trim_controls = trimmer.get_trim_controls(); % Get and set the trim controls
    sim_options.controller.static_output = trim_controls;
    
end

% Initialize the simulation state
supervisor.initialize_sim_state(sim_options);

% Initialize the vehicle controller
supervisor.initialize_controller(sim_options);

% Setup time vector
t_0 = sim_options.solver.t_0;
t_f = sim_options.solver.t_f;

if sim_options.visualization.draw_forces
    plot_forces(supervisor.gravity, supervisor.propulsion, supervisor.aerodynamics, 0, true);
end
if sim_options.visualization.draw_states
    plot_states(supervisor.vehicle, 0, true);
end

%% Begin simulation

fprintf('Starting simulation...\n');

% Main loop:
tic

% Choose ODE solver
if sim_options.solver.solver_type == 0 % Forward-Euler selected
    
    frame_num = 1;
    t = t_0;
    dt = sim_options.solver.dt;
    num_frames = (t_f-t_0)/dt;
    
    while (t_f - t > sim_options.solver.t_eps)
        
        % Calculate the state derivatives
        supervisor.sim_step(t);
        
        % Integrate the internal state with the calculated derivativess
        supervisor.integrate_fe();
        
        % Update visual output
        if sim_options.visualization.draw_graphics
            draw_aircraft(supervisor.vehicle, false);
        end
        if sim_options.visualization.draw_forces
            plot_forces(supervisor.gravity, supervisor.propulsion, supervisor.aerodynamics, t, false);
        end
        if sim_options.visualization.draw_states
            plot_states(supervisor.vehicle, t, false);
        end
        
        t = t + dt;
        frame_num = frame_num+1;
        
    end
    
    % Close the waitbar
    supervisor.close_waitbar();
    
    % Export simulation results
    if (sim_options.record_states)
        sim_output.array_time_states = supervisor.array_time_states;
        sim_output.array_states = supervisor.array_states;
    end
    if (sim_options.record_inputs)
        sim_output.array_time_inputs = supervisor.array_time_inputs;
        sim_output.array_inputs = supervisor.array_inputs;
    end    
    
elseif ismember(sim_options.solver.solver_type, [1 2]) % Matlab ode* requested
    
    % Set initial problem state
    y0 = supervisor.vehicle.state.serialize();
    % Set system function
    odefun = @supervisor.ode_eval;
    options = odeset(...
        'outputFcn', @supervisor.ode_outputFcn,...
        'Refine', 1 ...
        );
    
    if sim_options.solver.solver_type == 1 % If ode45 requested
        
        [t, y] = ode45(odefun, [t_0 t_f], y0, options);
        
    elseif sim_options.solver.solver_type == 2 % If ode15s requested
        
        [t, y] = ode15s(odefun, [t_0 t_f], y0, options);
        
    end
    
    % Export simulation results
    if (sim_options.record_states)
        sim_output.array_time_states = t';
        sim_output.array_states = y';
    end
    if (sim_options.record_inputs)
        warning('Using Matlab''s ode solvers does not allow saving of control inputs at the returned time vector');
        sim_output.array_time_inputs = supervisor.array_time_inputs;
        sim_output.array_inputs = supervisor.array_inputs;
    end
    
else
    error('Unsupported solver_type=%d specified',sim_options.solver.solver_type);
end

wall_time = toc;

fprintf('Simulation ended\n\n');

fprintf('Simulation duration: %f\n', t_f-t_0);
fprintf('Required wall time: %f\n', wall_time);
fprintf('Achieved speedup ratio: %f\n', (t_f-t_0)/wall_time);

% Restore warnign state
warning(warn_state);

end